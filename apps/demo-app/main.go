package main

import (
	"context"
	"database/sql"
	"fmt"
	"html/template"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	_ "github.com/lib/pq"
)

// Each pod holds exactly this many persistent DB connections.
// 2 pods × 10 = 20 (within postgres max_connections=30).
// 5 pods × 10 = 50 (exceeds postgres max_connections=30 → rejection).
const dbPoolSize = 10

// ── State ─────────────────────────────────────────────────────────────────────

type dbStatus struct {
	mu          sync.RWMutex
	connected   bool
	errMsg      string
	connCount   int // connections successfully held
	lastChecked time.Time
}

var (
	pool         *sql.DB
	heldConns    []*sql.Conn // persistent connections — held open for the pod lifetime
	heldMu       sync.Mutex
	state        dbStatus
	requestCount atomic.Int64
	startTime    = time.Now()
	tmpl         = template.Must(template.New("page").Parse(htmlPage))
)

// ── Helpers ───────────────────────────────────────────────────────────────────

func redactURL(raw string) string {
	u, err := url.Parse(raw)
	if err != nil || u.User == nil {
		return raw
	}
	if _, ok := u.User.Password(); ok {
		u.User = url.UserPassword(u.User.Username(), "***")
	}
	return u.String()
}

// ── Database pool ─────────────────────────────────────────────────────────────

func initPool() error {
	dbURL := os.Getenv("DATABASE_URL")
	u, err := url.Parse(dbURL)
	if err != nil || u.Host == "" {
		return fmt.Errorf("invalid DATABASE_URL: %q", dbURL)
	}
	db, err := sql.Open("postgres", dbURL)
	if err != nil {
		return fmt.Errorf("cannot open database: %w", err)
	}
	db.SetMaxOpenConns(dbPoolSize)
	db.SetMaxIdleConns(dbPoolSize)
	pool = db
	return nil
}

// releaseConnections closes all held connections and clears the slice.
func releaseConnections() {
	heldMu.Lock()
	defer heldMu.Unlock()
	for _, c := range heldConns {
		c.Close()
	}
	heldConns = heldConns[:0]
}

// holdConnections opens dbPoolSize persistent connections.
// Each call to db.Conn() acquires an exclusive connection from the pool
// that is held until conn.Close() is called — keeping it active in postgres.
func holdConnections() {
	if pool == nil {
		return
	}

	releaseConnections()

	log.Printf("[INFO]  Opening %d persistent DB connections (pod=%s)...",
		dbPoolSize, os.Getenv("POD_NAME"))

	heldMu.Lock()
	defer heldMu.Unlock()

	for i := 0; i < dbPoolSize; i++ {
		// Short timeout so a non-listening postgres (SYN drop) fails fast
		// instead of blocking for the OS TCP retransmit timeout (~2 min).
		connCtx, connCancel := context.WithTimeout(context.Background(), 5*time.Second)
		conn, err := pool.Conn(connCtx)
		connCancel()
		if err != nil {
			errStr := err.Error()
			state.mu.Lock()
			state.connected = false
			state.connCount = i
			state.lastChecked = time.Now()
			if strings.Contains(errStr, "too many clients") ||
				strings.Contains(errStr, "max_connections") {
				state.errMsg = fmt.Sprintf(
					"[ERROR] PostgreSQL rejected connection %d/%d: too many clients\n[ERROR] Database max_connections limit reached — reduce pod count or increase postgres max_connections",
					i+1, dbPoolSize,
				)
				log.Printf("[ERROR] PostgreSQL rejected connection %d/%d: too many clients (max_connections limit reached)",
					i+1, dbPoolSize)
			} else {
				state.errMsg = fmt.Sprintf("[ERROR] Cannot connect to database: %v", err)
				log.Printf("[ERROR] Cannot connect to database: %v", err)
			}
			state.mu.Unlock()
			return
		}

		// Verify the connection is alive
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		pingErr := conn.PingContext(ctx)
		cancel()
		if pingErr != nil {
			conn.Close()
			state.mu.Lock()
			state.connected = false
			state.connCount = i
			state.errMsg = fmt.Sprintf("[ERROR] DB connection %d/%d ping failed: %v", i+1, dbPoolSize, pingErr)
			state.lastChecked = time.Now()
			state.mu.Unlock()
			log.Printf("[ERROR] DB connection %d/%d ping failed: %v", i+1, dbPoolSize, pingErr)
			return
		}

		heldConns = append(heldConns, conn)
		log.Printf("[INFO]  DB connection %d/%d established", i+1, dbPoolSize)
	}

	state.mu.Lock()
	state.connected = true
	state.connCount = dbPoolSize
	state.errMsg = ""
	state.lastChecked = time.Now()
	state.mu.Unlock()

	log.Printf("[INFO]  DB pool ready: all %d connections established (pod=%s)",
		dbPoolSize, os.Getenv("POD_NAME"))
}

// checkAlive verifies that held connections are still alive.
// If connections dropped (e.g. postgres restarted), attempts to re-establish.
func checkAlive() {
	heldMu.Lock()
	count := len(heldConns)
	var alive bool
	if count > 0 {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		alive = heldConns[0].PingContext(ctx) == nil
		cancel()
	}
	heldMu.Unlock()

	if count < dbPoolSize || !alive {
		log.Printf("[INFO]  DB connections lost (%d/%d alive=%v), reconnecting...",
			count, dbPoolSize, alive)
		holdConnections()
	}
}

// ── HTTP handlers ─────────────────────────────────────────────────────────────

type pageData struct {
	Connected   bool
	DatabaseURL string
	Error       string
	Uptime      string
	Requests    int64
	LastChecked string
	PodName     string
	Namespace   string
	PoolSize    int
	ConnCount   int
}

func rootHandler(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	requestCount.Add(1)

	state.mu.RLock()
	data := pageData{
		Connected:   state.connected,
		DatabaseURL: redactURL(os.Getenv("DATABASE_URL")),
		Error:       state.errMsg,
		Uptime:      time.Since(startTime).Round(time.Second).String(),
		Requests:    requestCount.Load(),
		LastChecked: state.lastChecked.Format("15:04:05"),
		PodName:     os.Getenv("POD_NAME"),
		Namespace:   os.Getenv("POD_NAMESPACE"),
		PoolSize:    dbPoolSize,
		ConnCount:   state.connCount,
	}
	state.mu.RUnlock()

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Connection", "close") // force new TCP connection each refresh → round-robin across pods
	if err := tmpl.Execute(w, data); err != nil {
		http.Error(w, "template error", http.StatusInternalServerError)
	}
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	state.mu.RLock()
	connected := state.connected
	state.mu.RUnlock()

	w.Header().Set("Content-Type", "application/json")
	if connected {
		w.WriteHeader(http.StatusOK)
		fmt.Fprint(w, `{"status":"healthy"}`)
	} else {
		w.WriteHeader(http.StatusServiceUnavailable)
		fmt.Fprint(w, `{"status":"degraded","error":"database unreachable"}`)
	}
}

// ── Main ──────────────────────────────────────────────────────────────────────

func main() {
	if err := initPool(); err != nil {
		log.Printf("[ERROR] %v", err)
		state.mu.Lock()
		state.connected = false
		state.errMsg = fmt.Sprintf("[ERROR] %v", err)
		state.mu.Unlock()
	} else {
		holdConnections()
	}

	// Periodically verify connections are alive and reconnect if needed.
	// 3s interval: after a postgres restart ArgoCD takes ~10-15s to redeploy,
	// so we detect and reconnect within 3s of postgres being ready again.
	go func() {
		t := time.NewTicker(3 * time.Second)
		for range t.C {
			checkAlive()
		}
	}()

	http.HandleFunc("/", rootHandler)
	http.HandleFunc("/health", healthHandler)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	log.Printf("[INFO]  demo-app listening on :%s (%d connections/pod)", port, dbPoolSize)
	log.Fatal(http.ListenAndServe(":"+port, nil))
}

// ── HTML template ─────────────────────────────────────────────────────────────

const htmlPage = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta http-equiv="refresh" content="3">
  <title>demo-app · Status</title>
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    :root {
      --bg: #060d1a; --surface: #0d1829; --border: #1e2d45;
      --text: #c9d8ed; --muted: #4a6080;
      --green: #22c55e; --green-dim: rgba(34,197,94,.12);
      --red: #ef4444;   --red-dim:   rgba(239,68,68,.12);
      --mono: 'SF Mono','Fira Code','Consolas',monospace;
    }
    body { font-family: var(--mono); background: var(--bg); color: var(--text);
           min-height: 100vh; display: flex; flex-direction: column;
           align-items: center; justify-content: center; padding: 2rem; gap: 1.5rem; }
    .topbar { width: 100%; max-width: 760px; display: flex; align-items: center; justify-content: space-between; }
    .app-name { font-size: 1rem; color: var(--muted); letter-spacing: .15em; }
    .refresh-badge { font-size: .65rem; color: var(--muted); background: var(--surface);
                     border: 1px solid var(--border); padding: .25rem .6rem; border-radius: 99px; }
    .banner { width: 100%; max-width: 760px; border-radius: 1.25rem; border: 2px solid;
              padding: 3rem 2rem; text-align: center; }
    .banner.healthy  { background: var(--green-dim); border-color: var(--green); }
    .banner.degraded { background: var(--red-dim);   border-color: var(--red);
                       animation: glow-red 2s ease-in-out infinite; }
    @keyframes glow-red {
      0%,100% { box-shadow: 0 0 0 0 rgba(239,68,68,.2); }
      50%     { box-shadow: 0 0 40px 10px rgba(239,68,68,.15); } }
    .banner-icon  { font-size: 3.5rem; line-height: 1; margin-bottom: .75rem; }
    .banner-title { font-size: clamp(2.5rem,8vw,4rem); font-weight: 900; letter-spacing: .12em; }
    .banner.healthy  .banner-title { color: var(--green); }
    .banner.degraded .banner-title { color: var(--red); }
    .banner-sub { font-size: .9rem; margin-top: .5rem; color: var(--muted); }
    .error-box { width: 100%; max-width: 760px; background: rgba(127,29,29,.4);
                 border: 1px solid rgba(239,68,68,.35); border-radius: .75rem; padding: 1rem 1.25rem; }
    .error-label { font-size: .6rem; color: var(--red); letter-spacing: .2em; text-transform: uppercase; margin-bottom: .5rem; }
    .error-text  { font-size: .8rem; color: #fca5a5; white-space: pre-wrap; word-break: break-all; line-height: 1.6; }
    .grid { width: 100%; max-width: 760px; display: grid; grid-template-columns: 1fr 1fr; gap: .75rem; }
    .card { background: var(--surface); border: 1px solid var(--border); border-radius: .75rem; padding: 1rem 1.25rem; }
    .card.wide { grid-column: 1 / -1; }
    .card-label { font-size: .6rem; color: var(--muted); letter-spacing: .2em; text-transform: uppercase; margin-bottom: .4rem; }
    .card-value { font-size: .85rem; color: var(--text); word-break: break-all; }
    .dot { display: inline-block; width: 8px; height: 8px; border-radius: 50%; margin-right: 6px; vertical-align: middle; }
    .dot.green { background: var(--green); box-shadow: 0 0 6px var(--green); }
    .dot.red   { background: var(--red);   box-shadow: 0 0 6px var(--red); animation: blink 1s ease-in-out infinite; }
    @keyframes blink { 0%,100% { opacity: 1; } 50% { opacity: .25; } }
    .footer { font-size: .65rem; color: var(--muted); letter-spacing: .1em; }
  </style>
</head>
<body>
  <div class="topbar">
    <span class="app-name">◈ DEMO-APP</span>
    <span class="refresh-badge">auto-refresh · 3s</span>
  </div>

  {{if .Connected}}
  <div class="banner healthy">
    <div class="banner-icon">✅</div>
    <div class="banner-title">HEALTHY</div>
    <div class="banner-sub">All systems operational · Database connected</div>
  </div>
  {{else}}
  <div class="banner degraded">
    <div class="banner-icon">🔴</div>
    <div class="banner-title">DEGRADED</div>
    <div class="banner-sub">Database connection failure · Service unavailable</div>
  </div>
  {{end}}

  {{if .Error}}
  <div class="error-box">
    <div class="error-label">⚠ Error Details</div>
    <div class="error-text">{{.Error}}</div>
  </div>
  {{end}}

  <div class="grid">
    <div class="card wide">
      <div class="card-label">Database Connection</div>
      <div class="card-value">
        {{if .Connected}}<span class="dot green"></span>{{else}}<span class="dot red"></span>{{end}}
        {{.DatabaseURL}}
      </div>
    </div>
    <div class="card">
      <div class="card-label">DB Connections (this pod)</div>
      <div class="card-value">{{.ConnCount}} / {{.PoolSize}} held open</div>
    </div>
    <div class="card">
      <div class="card-label">Pod</div>
      <div class="card-value">{{if .PodName}}{{.PodName}}{{else}}local{{end}}</div>
    </div>
    <div class="card">
      <div class="card-label">Namespace</div>
      <div class="card-value">{{if .Namespace}}{{.Namespace}}{{else}}default{{end}}</div>
    </div>
    <div class="card">
      <div class="card-label">Uptime</div>
      <div class="card-value">{{.Uptime}}</div>
    </div>
    <div class="card">
      <div class="card-label">Requests Served</div>
      <div class="card-value">{{.Requests}}</div>
    </div>
    <div class="card wide">
      <div class="card-label">Last DB Check</div>
      <div class="card-value">{{.LastChecked}}</div>
    </div>
  </div>

  <div class="footer">GitOps managed by ArgoCD · {{.PoolSize}} connections/pod · demo-ia-ops</div>
</body>
</html>`
