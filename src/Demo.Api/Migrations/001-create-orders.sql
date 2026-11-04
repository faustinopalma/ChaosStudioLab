CREATE TABLE IF NOT EXISTS orders
(
    operation_id uuid PRIMARY KEY,
    payload_json jsonb NOT NULL,
    payload_sha256 char(64) NOT NULL,
    created_at_utc timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_orders_created_at_utc
    ON orders (created_at_utc);
