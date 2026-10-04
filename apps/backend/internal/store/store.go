package store

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

const schemaVersion = 1

type Message struct {
	ID        int64     `json:"id"`
	Text      string    `json:"text"`
	CreatedAt time.Time `json:"createdAt"`
}

type Store struct {
	pool *pgxpool.Pool
}

func Open(ctx context.Context, databaseURL string) (*Store, error) {
	config, err := pgxpool.ParseConfig(databaseURL)
	if err != nil {
		return nil, err
	}
	config.MaxConns = 5
	config.MinConns = 0
	config.MaxConnLifetime = time.Hour
	pool, err := pgxpool.NewWithConfig(ctx, config)
	if err != nil {
		return nil, err
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, err
	}
	return &Store{pool: pool}, nil
}

func (s *Store) Close() {
	s.pool.Close()
}

func (s *Store) Migrate(ctx context.Context) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(context.Background()) }()
	if _, err := tx.Exec(ctx, `CREATE TABLE IF NOT EXISTS schema_migrations (version integer PRIMARY KEY)`); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `CREATE TABLE IF NOT EXISTS messages (
		id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
		text text NOT NULL CHECK (char_length(text) BETWEEN 1 AND 280),
		created_at timestamptz NOT NULL DEFAULT now()
	)`); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `INSERT INTO schema_migrations (version) VALUES ($1) ON CONFLICT DO NOTHING`, schemaVersion); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func (s *Store) Ready(ctx context.Context) error {
	if err := s.pool.Ping(ctx); err != nil {
		return err
	}
	var present bool
	if err := s.pool.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM schema_migrations WHERE version = $1)`, schemaVersion).Scan(&present); err != nil {
		return err
	}
	if !present {
		return errors.New("schema migration is missing")
	}
	return nil
}

func (s *Store) List(ctx context.Context) ([]Message, error) {
	rows, err := s.pool.Query(ctx, `SELECT id, text, created_at FROM messages ORDER BY id DESC LIMIT 100`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := make([]Message, 0)
	for rows.Next() {
		var item Message
		if err := rows.Scan(&item.ID, &item.Text, &item.CreatedAt); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return items, nil
}

func (s *Store) Create(ctx context.Context, text string) (Message, error) {
	var item Message
	err := s.pool.QueryRow(ctx, `INSERT INTO messages (text) VALUES ($1) RETURNING id, text, created_at`, text).Scan(&item.ID, &item.Text, &item.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Message{}, errors.New("insert returned no message")
	}
	return item, err
}
