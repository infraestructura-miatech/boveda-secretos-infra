-- ════════════════════════════════════════════════════════════════
-- POSTGRESQL INITIALIZATION FOR VAULT TESTING
-- ════════════════════════════════════════════════════════════════
-- Este script inicializa la base de datos para testing de
-- dynamic database credentials con Vault
-- ════════════════════════════════════════════════════════════════

-- Crear schema de la aplicación
CREATE SCHEMA IF NOT EXISTS public;

-- Tabla de ejemplo: usuarios
CREATE TABLE IF NOT EXISTS public.users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Tabla de ejemplo: productos
CREATE TABLE IF NOT EXISTS public.products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    price DECIMAL(10, 2) NOT NULL,
    stock INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Tabla de ejemplo: orders
CREATE TABLE IF NOT EXISTS public.orders (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES public.users(id),
    total DECIMAL(10, 2) NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insertar datos de ejemplo
INSERT INTO public.users (username, email) VALUES
    ('alice', 'alice@example.com'),
    ('bob', 'bob@example.com'),
    ('charlie', 'charlie@example.com')
ON CONFLICT (username) DO NOTHING;

INSERT INTO public.products (name, description, price, stock) VALUES
    ('Laptop', 'High-performance laptop', 1299.99, 50),
    ('Mouse', 'Wireless mouse', 29.99, 200),
    ('Keyboard', 'Mechanical keyboard', 89.99, 150)
ON CONFLICT DO NOTHING;

-- Crear función para actualizar updated_at automáticamente
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger para actualizar updated_at en users
DROP TRIGGER IF EXISTS update_users_updated_at ON public.users;
CREATE TRIGGER update_users_updated_at
    BEFORE UPDATE ON public.users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Permisos para el usuario admin de Vault
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO vault_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO vault_admin;
GRANT ALL PRIVILEGES ON SCHEMA public TO vault_admin;

-- Permitir que vault_admin cree roles (necesario para dynamic credentials)
ALTER USER vault_admin WITH CREATEROLE;

-- Crear vista de ejemplo para demostrar permisos granulares
CREATE OR REPLACE VIEW public.user_orders AS
SELECT 
    u.username,
    u.email,
    o.id as order_id,
    o.total,
    o.status,
    o.created_at as order_date
FROM public.users u
LEFT JOIN public.orders o ON u.id = o.user_id;

GRANT SELECT ON public.user_orders TO vault_admin;

-- Log de inicialización
DO $$
BEGIN
    RAISE NOTICE '════════════════════════════════════════════════════════════════';
    RAISE NOTICE 'PostgreSQL Database Initialized for Vault Testing';
    RAISE NOTICE '════════════════════════════════════════════════════════════════';
    RAISE NOTICE 'Tables created:';
    RAISE NOTICE '  - users (% rows)', (SELECT COUNT(*) FROM public.users);
    RAISE NOTICE '  - products (% rows)', (SELECT COUNT(*) FROM public.products);
    RAISE NOTICE '  - orders (% rows)', (SELECT COUNT(*) FROM public.orders);
    RAISE NOTICE '';
    RAISE NOTICE 'Vault admin user: vault_admin';
    RAISE NOTICE 'Database: testdb';
    RAISE NOTICE '';
    RAISE NOTICE 'Ready for dynamic credential creation!';
    RAISE NOTICE '════════════════════════════════════════════════════════════════';
END $$;
