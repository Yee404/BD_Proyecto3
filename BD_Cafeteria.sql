-- Universidad del Valle de Guatemala
-- CC3088 Base de Datos
-- (Ciclo 1 ‑ 2025)

-- SISTEMA DE CONTROL DE PEDIDOS EN UNA CAFETERÍA

-- Grupo 6
-- Abner Gabriel Mejicanos
-- Alejandro Rivera
-- María José Yee


-- -----------------------------------------------------------
-- 1. CREACIÓN DE LAS TABLAS

select current_database();

select * from clientes;


CREATE TABLE clientes (
    id_cliente  SERIAL PRIMARY KEY,
    nombre_cliente TEXT NOT NULL,
    email_cliente  TEXT UNIQUE,
    fecha_creacion_cliente TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (
        email_cliente IS NULL
        OR email_cliente ~* E'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$'
    )
);

CREATE TABLE telefono_clientes (
    id_cliente       INTEGER REFERENCES clientes(id_cliente) ON DELETE CASCADE,
    telefono_cliente TEXT    NOT NULL
                           CHECK (telefono_cliente ~ '^[0-9-]{7,15}$'),
	fecha_registro   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_cliente, telefono_cliente)
);

CREATE TABLE empleados (
    id_empleado     SERIAL PRIMARY KEY,
    nombre_empleado TEXT   NOT NULL,
    rol_empleado    TEXT   NOT NULL
                         CHECK (rol_empleado IN ('barista','cajero','mesero','gerente')),
    fecha_contrato  DATE NOT NULL DEFAULT CURRENT_DATE, 
    email_empleado  TEXT   UNIQUE
);

CREATE TABLE categorias (
    id_categoria      SERIAL PRIMARY KEY,
    nombre_categoria  TEXT   NOT NULL UNIQUE,
    CHECK (char_length(nombre_categoria) > 1)
);

CREATE TABLE productos (
    id_producto      SERIAL PRIMARY KEY,
    id_categoria     INTEGER REFERENCES categorias(id_categoria),
    nombre_producto  TEXT    NOT NULL UNIQUE,
    descripcion      TEXT,
    precio           NUMERIC(7,2) NOT NULL CHECK (precio > 0),
    activo           BOOLEAN      NOT NULL DEFAULT TRUE
);

CREATE TABLE proveedores (
    id_proveedor       SERIAL PRIMARY KEY,
    nombre_proveedor   TEXT NOT NULL UNIQUE,
    contacto_proveedor TEXT,
	fecha_registro     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
    CHECK (char_length(nombre_proveedor) > 1)
);

CREATE TABLE telefonos_proveedores (
    id_proveedor       INTEGER REFERENCES proveedores(id_proveedor) ON DELETE CASCADE,
    telefono_proveedor TEXT    NOT NULL
                              CHECK (telefono_proveedor ~ '^[0-9-]{7,15}$'),
	fecha_registro     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_proveedor, telefono_proveedor)
);

CREATE TABLE productos_proveedores (
    id_producto  INTEGER REFERENCES productos(id_producto)   ON DELETE CASCADE,
    id_proveedor INTEGER REFERENCES proveedores(id_proveedor) ON DELETE CASCADE,
    plazo_dias   INTEGER NOT NULL DEFAULT 3  CHECK (plazo_dias > 0),
    costo        NUMERIC(7,2) NOT NULL        CHECK (costo > 0),
    PRIMARY KEY (id_producto, id_proveedor)
);

CREATE TABLE mesas_cafe (
    id_mesa  SERIAL PRIMARY KEY,
    codigo   TEXT    NOT NULL UNIQUE,
    asientos INTEGER NOT NULL CHECK (asientos BETWEEN 1 AND 8)
);

CREATE TABLE pedidos (
    id_pedido         SERIAL PRIMARY KEY,
    id_cliente        INTEGER REFERENCES clientes(id_cliente),
    id_empleado       INTEGER REFERENCES empleados(id_empleado),
    id_mesa           INTEGER REFERENCES mesas_cafe(id_mesa),
    fecha_hora_pedido TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    estado_pedido     TEXT      NOT NULL DEFAULT 'abierta'
                              CHECK (estado_pedido IN ('abierta','preparacion','lista','entregada','cancelada')),
    total             NUMERIC(10,2) NOT NULL DEFAULT 0
);

CREATE TABLE items_orden (
    id_pedido       INTEGER REFERENCES pedidos(id_pedido)   ON DELETE CASCADE,
    id_producto     INTEGER REFERENCES productos(id_producto),
    cantidad        INTEGER      NOT NULL CHECK (cantidad > 0),
    precio_unitario NUMERIC(7,2) NOT NULL CHECK (precio_unitario > 0), -- autocompletado
    precio_total    NUMERIC(9,2) NOT NULL,                              -- qty*precio_unitario
	fecha_registro  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_pedido, id_producto)
);

CREATE TABLE pagos (
    id_pago      SERIAL PRIMARY KEY,
    id_pedido    INTEGER REFERENCES pedidos(id_pedido) ON DELETE CASCADE,
    monto        NUMERIC(10,2) NOT NULL CHECK (monto > 0),
    metodo_pago  TEXT          NOT NULL CHECK (metodo_pago IN ('efectivo','tarjeta','transferencia')),
    fecha_pago   TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
);



-- 2. CREACIÓN FUNCIONES Y TRIGGERS

-- Función 1
-- Antes de INSERT/UPDATE ON items_orden → calcular precios
CREATE OR REPLACE FUNCTION trg_items_orden_set_prices()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.precio_unitario IS NULL THEN
        SELECT precio
          INTO NEW.precio_unitario
          FROM productos
         WHERE id_producto = NEW.id_producto;
    END IF;

    NEW.precio_total := NEW.precio_unitario * NEW.cantidad;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger
CREATE TRIGGER before_items_orden_set_prices
BEFORE INSERT OR UPDATE ON items_orden
FOR EACH ROW
EXECUTE FUNCTION trg_items_orden_set_prices();




-- Función 2
-- Después de INSERT/UPDATE/DELETE ON items_orden → actualizar total del pedido
CREATE OR REPLACE FUNCTION trg_pedidos_update_total()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE pedidos
       SET total = COALESCE(
                  (SELECT SUM(precio_total)
                     FROM items_orden
                    WHERE id_pedido = COALESCE(NEW.id_pedido, OLD.id_pedido)), 0)
     WHERE id_pedido = COALESCE(NEW.id_pedido, OLD.id_pedido);
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;


-- Trigger
CREATE TRIGGER after_items_orden_update_total
AFTER INSERT OR UPDATE OR DELETE ON items_orden
FOR EACH ROW
EXECUTE FUNCTION trg_pedidos_update_total();




-- Función 3
-- Antes de INSERT ON pagos → evitar sobre-pago
CREATE OR REPLACE FUNCTION trg_pagos_check_monto()
RETURNS TRIGGER AS $$
DECLARE
    pagado          NUMERIC(10,2);
    total_pedido    NUMERIC(10,2);
    estado          TEXT;
BEGIN
    SELECT total, estado_pedido
      INTO total_pedido, estado
      FROM pedidos
     WHERE id_pedido = NEW.id_pedido;

-- si el pedido está cancelado, no hacemos validación;

    IF estado = 'cancelada' THEN
        RETURN NEW;
    END IF;

	SELECT COALESCE(SUM(monto),0)
      INTO pagado
      FROM pagos
     WHERE id_pedido = NEW.id_pedido;

    IF NEW.monto + pagado > total_pedido THEN
        RAISE EXCEPTION
          'Pago excede el saldo del pedido (total: %, pagado: %, nuevo pago: %)',
          total_pedido, pagado, NEW.monto;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- Trigger
CREATE TRIGGER before_pagos_check_monto
BEFORE INSERT ON pagos
FOR EACH ROW
EXECUTE FUNCTION trg_pagos_check_monto();




-- Funcion4
-- Evitar que los pedidos cancelados estén en pagos
CREATE OR REPLACE FUNCTION trg_bloquear_pago_cancelado()
RETURNS TRIGGER AS $$
DECLARE
    estado TEXT;
BEGIN
    SELECT estado_pedido
      INTO estado
      FROM pedidos
     WHERE id_pedido = NEW.id_pedido;

    IF estado = 'cancelada' THEN
        RAISE EXCEPTION
          'No se pueden registrar pagos en un pedido cancelado (id=%).',
          NEW.id_pedido;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger
CREATE TRIGGER before_pago_cancelado
BEFORE INSERT OR UPDATE ON pagos
FOR EACH ROW
EXECUTE FUNCTION trg_bloquear_pago_cancelado();



-- -----------------------------------------------------------
-- 3. GENERADOR DE DATOS
-- (variedad de estados, fechas y pagos)

DO $$
DECLARE
    i           INT;
    v_pedido    INT;
    v_estado    TEXT;
    v_met_pago  TEXT;
    v_fecha     TIMESTAMP;
BEGIN
    ------------------------------------------------------------------
    -- 1) 100 clientes
    FOR i IN 1..100 LOOP
        INSERT INTO clientes (nombre_cliente, email_cliente)
        VALUES (format('Cliente %s', i),
                format('cliente%s@mail.com', i));
    END LOOP;

    ------------------------------------------------------------------
    -- 2) 20 categorías
    FOR i IN 1..20 LOOP
        INSERT INTO categorias (nombre_categoria)
        VALUES (format('Categoria %s', i));
    END LOOP;

    ------------------------------------------------------------------
    -- 3) 100 productos
    FOR i IN 1..100 LOOP
        INSERT INTO productos (id_categoria, nombre_producto, precio)
        VALUES (
            1 + (random()*19)::INT,            -- categoría 1-20
            format('Producto %s', i),
            round((10 + random()*40)::NUMERIC, 2)
        );
    END LOOP;

    ------------------------------------------------------------------
    -- 4) 30 mesas
    FOR i IN 1..30 LOOP
        INSERT INTO mesas_cafe (codigo, asientos)
        VALUES (format('M%s', i), 1 + (random()*7)::INT);
    END LOOP;

    ------------------------------------------------------------------
    -- 5) 5 empleados reales
    INSERT INTO empleados (nombre_empleado, rol_empleado)
    VALUES ('Empl 1','cajero'),
           ('Empl 2','barista'),
           ('Empl 3','mesero'),
           ('Empl 4','mesero'),
           ('Empl 5','gerente');

    ------------------------------------------------------------------
    -- 6) 400 pedidos  + items (+ pago si no cancelado)
    FOR i IN 1..400 LOOP
        ----------------------------------------------------------------
        -- a) elegir fecha y estado aleatorios
        v_fecha  := NOW() - ((floor(random()*15)) || ' days')::interval;
        v_estado := (ARRAY['abierta','preparacion','lista',
                           'entregada','cancelada'])[1+floor(random()*5)];

        INSERT INTO pedidos (id_cliente, id_empleado, id_mesa,
                             fecha_hora_pedido, estado_pedido)
        VALUES (
            1 + (random()*99)::INT,          -- cliente 1-100
            1 + (random()*4)::INT,           -- empleado 1-5
            1 + (random()*29)::INT,          -- mesa 1-30
            v_fecha,
            v_estado
        )
        RETURNING id_pedido INTO v_pedido;

        ----------------------------------------------------------------
        -- b) 1-5 items por pedido
        FOR _ IN 1..(1 + (random()*4)::INT) LOOP
            INSERT INTO items_orden (id_pedido, id_producto, cantidad)
            VALUES (
                v_pedido,
                1 + (random()*99)::INT,      -- producto 1-100
                1 + (random()*3)::INT        -- cantidad 1-4
            )
            ON CONFLICT (id_pedido, id_producto) DO NOTHING;
        END LOOP;

        ----------------------------------------------------------------
        -- c) insertar pago solo si el pedido NO está cancelado
        IF v_estado <> 'cancelada' THEN
            -- método de pago aleatorio
            v_met_pago :=
              (ARRAY['efectivo','tarjeta','transferencia'])
              [1+floor(random()*3)];

            INSERT INTO pagos (id_pedido, monto, metodo_pago)
            SELECT v_pedido, total, v_met_pago
            FROM   pedidos
            WHERE  id_pedido = v_pedido;
        END IF;
    END LOOP;
END $$;


-- Comprobar la creación de datos
SELECT count(*) FROM clientes;        -- 100
SELECT count(*) FROM categorias;      -- 20
SELECT count(*) FROM productos;       -- 100
SELECT count(*) FROM pedidos;         -- 400
SELECT count(*) FROM items_orden;     -- debería rondar entre 800-1600
SELECT count(*) FROM pagos; 
SELECT count(*) FROM empleados;

-- Comprobar tablas
Select * from clientes;
Select * from categorias;
Select * from productos;
Select * from empleados;
Select * from pedidos;
Select * from pagos;

















-- =======================================================
-- =======================================================
-- PRUEBAS PERSONALES DE VISTAS (IGNORAR)

select current_database();


Select * from empleados;
Select * from pedidos;
Select * from pagos;


-- Arrglar error con correos
ALTER TABLE clientes
  DROP CONSTRAINT clientes_email_cliente_check;

ALTER TABLE clientes
  ADD CONSTRAINT clientes_email_cliente_check
  CHECK (
      email_cliente IS NULL
      OR email_cliente ~* E'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$'
  );


-- Borrar todo durante el desarrollo de los datos
 TRUNCATE TABLE
    pagos,
    items_orden,
    pedidos,
    telefono_clientes,
    clientes,
    productos,
    categorias,
    mesas_cafe,
    proveedores,
    telefonos_proveedores,
    productos_proveedores,
    empleados
    RESTART IDENTITY CASCADE; 



-- COLOCAR MÁS VARIEDAD DE ESTADOS
-- Los primeros 50 pedidos a 'preparación'
UPDATE pedidos
SET    estado_pedido = 'preparacion'
WHERE  id_pedido BETWEEN 1 AND 50;

-- Los siguientes 100 a 'lista'
UPDATE pedidos
SET    estado_pedido = 'lista'
WHERE  id_pedido BETWEEN 51 AND 150;

-- Otros 100 a 'entregada'
UPDATE pedidos
SET    estado_pedido = 'entregada'
WHERE  id_pedido BETWEEN 151 AND 250;

-- de 250 a 320 en cancelados
UPDATE pedidos
SET    estado_pedido = 'cancelada'
WHERE  id_pedido BETWEEN 151 AND 250;




-- CAMBIAR ESTADO QUITANDO TILDE
UPDATE pedidos
SET    estado_pedido = 'preparación'
WHERE  estado_pedido = 'preparación';




-- MÁS VARIEDAD EN LOS DÍAS DE PEDIDOS
UPDATE pedidos
SET    fecha_hora_pedido = fecha_hora_pedido - INTERVAL '7 days'
WHERE  id_pedido BETWEEN 1 AND 50;

-- Aleatoriza entre 1 y 14 días atrás para los pedidos 51-150
UPDATE pedidos
SET    fecha_hora_pedido =
       fecha_hora_pedido - ( (1 + floor(random()*14)) || ' days')::interval
WHERE  id_pedido BETWEEN 51 AND 150;




-- MÁS VARIEDAD DE METODO DE PAGO
UPDATE pagos
SET    metodo_pago = 'tarjeta'
WHERE  id_pedido BETWEEN 1 AND 50;

UPDATE pagos
SET    metodo_pago = 'transferencia'
WHERE  id_pedido BETWEEN 51 AND 150;


-- Hay un error, y es que sí o sí debe de haber un método de pago aunque el pedido se encuentre cancelado
-- quitar el null
ALTER TABLE pagos
  ALTER COLUMN metodo_pago DROP NOT NULL,
  ALTER COLUMN monto        DROP NOT NULL;

-- reemplazar el check para que acepte null
ALTER TABLE pagos
  DROP CONSTRAINT pagos_metodo_pago_check;

ALTER TABLE pagos
  ADD  CONSTRAINT pagos_metodo_pago_check
  CHECK (
      metodo_pago IS NULL
      OR metodo_pago IN ('efectivo','tarjeta','transferencia')
  );

-- crear función para bloquear que se registre en pagos si un pedido se encuentra cancelado
-- estará arriba con los demás triggers y funciones,
-- pero primero se elimina si es que ya existía un trigger
DROP TRIGGER IF EXISTS before_pago_cancelado ON pagos;
