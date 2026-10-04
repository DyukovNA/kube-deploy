package api

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"

	"kubedeploy/backend/internal/store"
)

type MessageStore interface {
	Ready(context.Context) error
	List(context.Context) ([]store.Message, error)
	Create(context.Context, string) (store.Message, error)
}

type API struct {
	store   MessageStore
	logger  *slog.Logger
	version string
	commit  string
}

func New(messageStore MessageStore, logger *slog.Logger, version, commit string) *API {
	return &API{store: messageStore, logger: logger, version: version, commit: commit}
}

func (a *API) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/health/live", a.live)
	mux.HandleFunc("GET /api/health/ready", a.ready)
	mux.HandleFunc("GET /api/version", a.getVersion)
	mux.HandleFunc("GET /api/messages", a.listMessages)
	mux.HandleFunc("POST /api/messages", a.createMessage)
	return mux
}

func (a *API) live(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (a *API) ready(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()
	if err := a.store.Ready(ctx); err != nil {
		a.logger.Warn("readiness failed", "error", err)
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "unavailable"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (a *API) getVersion(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"version": a.version, "commit": a.commit})
}

func (a *API) listMessages(w http.ResponseWriter, r *http.Request) {
	items, err := a.store.List(r.Context())
	if err != nil {
		a.logger.Error("list messages failed", "error", err)
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "database unavailable"})
		return
	}
	writeJSON(w, http.StatusOK, items)
}

func (a *API) createMessage(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, 4096)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	var input struct {
		Text string `json:"text"`
	}
	if err := decoder.Decode(&input); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON body"})
		return
	}
	if err := decoder.Decode(new(any)); !errors.Is(err, io.EOF) {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "only one JSON object is allowed"})
		return
	}
	input.Text = strings.TrimSpace(input.Text)
	length := utf8.RuneCountInString(input.Text)
	if length < 1 || length > 280 || !utf8.ValidString(input.Text) {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "text must contain 1 to 280 Unicode characters"})
		return
	}
	item, err := a.store.Create(r.Context(), input.Text)
	if err != nil {
		a.logger.Error("create message failed", "error", err)
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "database unavailable"})
		return
	}
	writeJSON(w, http.StatusCreated, item)
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}
