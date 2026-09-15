-- =====================================================================
-- PROYECTO BASE DE DATOS AVANZADA - E-COMMERCE
-- Archivo 01: Esquema y Datos

-- =====================================================================

DROP DATABASE IF EXISTS ecommerce_db;
CREATE DATABASE ecommerce_db
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_0900_ai_ci;
USE ecommerce_db;


-- =====================================================================
-- SECCION 1: TABLAS DEL NUCLEO DEL NEGOCIO
-- =====================================================================

-- ---------------------------------------------------------------------
-- categorias: sistema de clasificacion de los productos
-- ---------------------------------------------------------------------
CREATE TABLE categorias (
    id_categoria INT AUTO_INCREMENT PRIMARY KEY,
    nombre       VARCHAR(80) NOT NULL UNIQUE,
    descripcion  TEXT
) ENGINE=InnoDB;


-- ---------------------------------------------------------------------
-- proveedores: entidades que suministran los productos
-- ---------------------------------------------------------------------
CREATE TABLE proveedores (
    id_proveedor      INT AUTO_INCREMENT PRIMARY KEY,
    nombre            VARCHAR(150) NOT NULL,
    email_contacto    VARCHAR(150) UNIQUE,
    telefono_contacto VARCHAR(30)
) ENGINE=InnoDB;


-- ---------------------------------------------------------------------
-- productos: catalogo de articulos a la venta
--
-- id_categoria se deja NULL-able a proposito: el trigger
-- trg_assign_default_category_on_null (archivo 05) asigna la categoria
-- 'General' cuando se inserta un producto sin clasificar.
-- ---------------------------------------------------------------------
CREATE TABLE productos (
    id_producto        INT AUTO_INCREMENT PRIMARY KEY,
    nombre             VARCHAR(150) NOT NULL UNIQUE,
    descripcion        TEXT,
    precio             DECIMAL(12,2) NOT NULL,
    costo              DECIMAL(12,2) NOT NULL,
    stock              INT NOT NULL DEFAULT 0,
    stock_minimo       INT NOT NULL DEFAULT 10,
    sku                VARCHAR(40) NOT NULL UNIQUE,
    peso_kg            DECIMAL(8,3) NOT NULL DEFAULT 0,
    ubicacion          VARCHAR(100),
    fecha_creacion     DATETIME DEFAULT CURRENT_TIMESTAMP,
    fecha_modificacion DATETIME DEFAULT NULL,
    activo             BOOLEAN DEFAULT TRUE,
    id_categoria       INT NULL,
    id_proveedor       INT NOT NULL,
    CONSTRAINT fk_producto_categoria
        FOREIGN KEY (id_categoria) REFERENCES categorias(id_categoria),
    CONSTRAINT fk_producto_proveedor
        FOREIGN KEY (id_proveedor) REFERENCES proveedores(id_proveedor),
    CONSTRAINT chk_producto_precio       CHECK (precio > 0),
    CONSTRAINT chk_producto_costo        CHECK (costo >= 0),
    CONSTRAINT chk_producto_stock        CHECK (stock >= 0),
    CONSTRAINT chk_producto_stock_minimo CHECK (stock_minimo >= 0)
) ENGINE=InnoDB;


-- ---------------------------------------------------------------------
-- clientes: usuarios registrados que realizan compras
-- ---------------------------------------------------------------------
CREATE TABLE clientes (
    id_cliente          INT AUTO_INCREMENT PRIMARY KEY,
    nombre              VARCHAR(80) NOT NULL,
    apellido            VARCHAR(80) NOT NULL,
    email               VARCHAR(150) NOT NULL UNIQUE,
    contrasena          VARCHAR(255) NOT NULL,
    direccion_envio     VARCHAR(255),
    fecha_nacimiento    DATE NULL,
    fecha_registro      DATETIME DEFAULT CURRENT_TIMESTAMP,
    activo              BOOLEAN DEFAULT TRUE,
    total_gastado       DECIMAL(14,2) NOT NULL DEFAULT 0,
    fecha_ultimo_pedido DATETIME DEFAULT NULL,
    CONSTRAINT chk_cliente_total_gastado CHECK (total_gastado >= 0)
) ENGINE=InnoDB;


-- ---------------------------------------------------------------------
-- ventas: encabezado de la orden
-- ---------------------------------------------------------------------
CREATE TABLE ventas (
    id_venta    INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente  INT NOT NULL,
    fecha_venta DATETIME DEFAULT CURRENT_TIMESTAMP,
    estado      ENUM('Pendiente de Pago','Procesando','Enviado','Entregado','Cancelado')
                NOT NULL DEFAULT 'Pendiente de Pago',
    total       DECIMAL(14,2) NOT NULL DEFAULT 0,
    CONSTRAINT fk_venta_cliente
        FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente),
    CONSTRAINT chk_venta_total CHECK (total >= 0)
) ENGINE=InnoDB;


-- ---------------------------------------------------------------------
-- detalle_ventas: lineas de la orden (puente ventas <-> productos)
--
-- precio_unitario_congelado guarda el precio del momento de la compra.
-- No se referencia productos.precio porque ese valor cambia con el
-- tiempo y el historico de la venta debe quedar intacto.
-- ---------------------------------------------------------------------
CREATE TABLE detalle_ventas (
    id_detalle                INT AUTO_INCREMENT PRIMARY KEY,
    id_venta                  INT NOT NULL,
    id_producto               INT NOT NULL,
    cantidad                  INT NOT NULL,
    precio_unitario_congelado DECIMAL(12,2) NOT NULL,
    CONSTRAINT fk_detalle_venta
        FOREIGN KEY (id_venta) REFERENCES ventas(id_venta),
    CONSTRAINT fk_detalle_producto
        FOREIGN KEY (id_producto) REFERENCES productos(id_producto),
    CONSTRAINT chk_detalle_cantidad CHECK (cantidad > 0),
    CONSTRAINT chk_detalle_precio   CHECK (precio_unitario_congelado >= 0)
) ENGINE=InnoDB;


-- ---------------------------------------------------------------------
-- promociones: campañas de descuento con vigencia
-- La usa el evento evt_deactivate_expired_promotions_hourly (archivo 06)
-- ---------------------------------------------------------------------
CREATE TABLE promociones (
    id_promocion INT AUTO_INCREMENT PRIMARY KEY,
    codigo       VARCHAR(40) NOT NULL UNIQUE,
    descripcion  VARCHAR(255),
    porcentaje   DECIMAL(5,2) NOT NULL,
    fecha_inicio DATETIME NOT NULL,
    fecha_fin    DATETIME NOT NULL,
    activa       BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT chk_promocion_porcentaje CHECK (porcentaje > 0 AND porcentaje <= 100),
    CONSTRAINT chk_promocion_fechas     CHECK (fecha_fin > fecha_inicio)
) ENGINE=InnoDB;


-- =====================================================================
-- SECCION 2: TABLAS DE AUDITORIA, LOG Y REPORTE
--
-- Se declaran aqui para que el esquema quede completo en un solo
-- archivo y para que 04_Seguridad.sql pueda otorgar permisos sobre
-- ellas. Los archivos 05 y 06 las vuelven a declarar con
-- CREATE TABLE IF NOT EXISTS para poder ejecutarse de forma aislada.
-- =====================================================================

-- log de cambios de precio (la escribe trg_audit_precio_producto_after_update)
CREATE TABLE log_cambios_precio (
    id_auditoria     INT AUTO_INCREMENT PRIMARY KEY,
    id_producto      INT NOT NULL,
    nombre_producto  VARCHAR(150),
    precio_anterior  DECIMAL(12,2),
    precio_nuevo     DECIMAL(12,2),
    diferencia       DECIMAL(12,2),
    porcentaje_cambio DECIMAL(10,2),
    usuario          VARCHAR(100) DEFAULT 'sistema',
    fecha_cambio     DATETIME DEFAULT CURRENT_TIMESTAMP,
    razon_cambio     VARCHAR(255),
    CONSTRAINT fk_logprecio_producto
        FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
) ENGINE=InnoDB;

-- log de altas de clientes (la escribe trg_log_new_customer_after_insert)
CREATE TABLE log_clientes (
    id_log       INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente   INT NOT NULL,
    nombre       VARCHAR(80),
    apellido     VARCHAR(80),
    email        VARCHAR(150),
    accion       VARCHAR(50),
    fecha_evento DATETIME DEFAULT CURRENT_TIMESTAMP,
    ip_origen    VARCHAR(45),
    detalles     TEXT,
    CONSTRAINT fk_logcliente_cliente
        FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente)
) ENGINE=InnoDB;

-- bitacora de ejecucion de los eventos programados
CREATE TABLE log_ejecucion_eventos (
    id_log          INT AUTO_INCREMENT PRIMARY KEY,
    nombre_evento   VARCHAR(100) NOT NULL,
    filas_afectadas INT,
    fecha_ejecucion DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- historico de la bitacora (la llena evt_archive_old_logs_monthly)
CREATE TABLE log_ejecucion_eventos_historico LIKE log_ejecucion_eventos;

-- reporte semanal (lo llena evt_generate_weekly_sales_report)
CREATE TABLE reporte_ventas_semanales (
    id_reporte      INT AUTO_INCREMENT PRIMARY KEY,
    semana_inicio   DATE NOT NULL UNIQUE,
    semana_fin      DATE NOT NULL,
    cantidad_ventas INT NOT NULL,
    total_vendido   DECIMAL(14,2) NOT NULL,
    fecha_generado  DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- niveles de lealtad (los recalcula evt_recalculate_customer_loyalty_tiers_nightly)
CREATE TABLE niveles_lealtad_clientes (
    id_cliente     INT PRIMARY KEY,
    total_gastado  DECIMAL(14,2) NOT NULL,
    nivel          VARCHAR(20) NOT NULL,
    fecha_calculo  DATETIME DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_lealtad_cliente
        FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente)
) ENGINE=InnoDB;

-- lista de reabastecimiento (la llena evt_generate_reorder_list_daily)
CREATE TABLE lista_reabastecimiento (
    id_lista          INT AUTO_INCREMENT PRIMARY KEY,
    fecha_lista       DATE NOT NULL,
    id_producto       INT NOT NULL,
    stock_actual      INT NOT NULL,
    stock_minimo      INT NOT NULL,
    cantidad_sugerida INT NOT NULL,
    CONSTRAINT fk_reabastecimiento_producto
        FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
) ENGINE=InnoDB;

-- resumen diario (lo llena evt_aggregate_daily_sales_data)
CREATE TABLE resumen_ventas_diarias (
    fecha           DATE PRIMARY KEY,
    cantidad_ventas INT NOT NULL,
    total_vendido   DECIMAL(14,2) NOT NULL
) ENGINE=InnoDB;

-- inconsistencias (las detecta evt_check_data_consistency_nightly)
CREATE TABLE inconsistencias_detectadas (
    id_inconsistencia INT AUTO_INCREMENT PRIMARY KEY,
    tipo              VARCHAR(100) NOT NULL,
    id_venta          INT NOT NULL,
    fecha_revision    DATE NOT NULL
) ENGINE=InnoDB;


-- =====================================================================
-- SECCION 3: INDICES DE APOYO
-- Aceleran los JOIN y los filtros que usan las consultas del archivo 02.
-- =====================================================================

CREATE INDEX idx_producto_categoria   ON productos(id_categoria);
CREATE INDEX idx_producto_proveedor   ON productos(id_proveedor);
CREATE INDEX idx_producto_stock       ON productos(stock);
CREATE INDEX idx_venta_cliente        ON ventas(id_cliente);
CREATE INDEX idx_venta_fecha          ON ventas(fecha_venta);
CREATE INDEX idx_venta_estado         ON ventas(estado);
CREATE INDEX idx_detalle_venta        ON detalle_ventas(id_venta);
CREATE INDEX idx_detalle_producto     ON detalle_ventas(id_producto);
CREATE INDEX idx_cliente_registro     ON clientes(fecha_registro);


-- =====================================================================
-- SECCION 4: DATOS DE EJEMPLO
-- =====================================================================

-- --------------------------- categorias ------------------------------
INSERT INTO categorias (id_categoria, nombre, descripcion) VALUES
(1, 'Electronica', 'Dispositivos electronicos y accesorios'),
(2, 'Ropa',        'Prendas de vestir'),
(3, 'Hogar',       'Articulos para la casa'),
(4, 'Deportes',    'Implementos deportivos'),
(5, 'Libros',      'Libros y revistas'),
(6, 'General',     'Categoria por defecto para productos sin clasificacion');

-- --------------------------- proveedores -----------------------------
INSERT INTO proveedores (id_proveedor, nombre, email_contacto, telefono_contacto) VALUES
(1, 'TecnoAndina SAS',        'ventas@tecnoandina.com',     '6076543210'),
(2, 'Importadora Digital',    'contacto@impdigital.com',    '6012345678'),
(3, 'Textiles del Oriente',   'compras@textilesoriente.co', '6076781234'),
(4, 'Casa y Cocina SA',       'proveedor@casaycocina.com',  '6044448899'),
(5, 'Deportes Total',         'info@deportestotal.com',     '6023216547');

-- --------------------------- productos -------------------------------
-- stock_minimo se define segun el precio: entre mas caro el producto,
-- menos unidades conviene tener en bodega.
INSERT INTO productos
    (id_producto, nombre, descripcion, precio, costo, stock, stock_minimo,
     sku, peso_kg, ubicacion, fecha_creacion, activo, id_categoria, id_proveedor) VALUES
( 1, 'Laptop Vortex 14',          'Portatil 14 pulgadas 16GB RAM SSD 512GB', 3200000, 2400000,  25,  5, 'ELE-LAP-001',  1.600, 'A-01-01', '2025-09-01 08:00:00', TRUE, 1, 1),
( 2, 'Mouse Inalambrico Nova',    'Mouse optico inalambrico 2.4GHz',           85000,   48000, 120, 20, 'ELE-MOU-002',  0.120, 'A-01-02', '2025-09-01 08:05:00', TRUE, 1, 1),
( 3, 'Teclado Mecanico K80',      'Teclado mecanico switch azul',             320000,  195000,  40, 15, 'ELE-TEC-003',  0.900, 'A-01-03', '2025-09-03 09:30:00', TRUE, 1, 2),
( 4, 'Audifonos Bluetooth Pulse', 'Audifonos con cancelacion de ruido',       240000,  130000,   8, 15, 'ELE-AUD-004',  0.300, 'A-02-01', '2025-09-05 10:15:00', TRUE, 1, 2),
( 5, 'Camiseta Algodon Basica',   'Camiseta 100% algodon varios colores',      55000,   22000, 200, 20, 'ROP-CAM-005',  0.250, 'B-01-01', '2025-09-10 11:00:00', TRUE, 2, 3),
( 6, 'Jean Slim Fit',             'Pantalon jean corte slim',                 145000,   70000,  60, 20, 'ROP-JEA-006',  0.700, 'B-01-02', '2025-09-10 11:10:00', TRUE, 2, 3),
( 7, 'Cafetera Express Milano',   'Cafetera express 15 bares',                480000,  300000,  18, 15, 'HOG-CAF-007',  4.200, 'C-01-01', '2025-09-15 14:20:00', TRUE, 3, 4),
( 8, 'Juego de Sabanas King',     'Sabanas 400 hilos tamano king',            190000,   95000,   5, 20, 'HOG-SAB-008',  1.800, 'C-01-02', '2025-09-15 14:35:00', TRUE, 3, 4),
( 9, 'Balon de Futbol Pro',       'Balon profesional numero 5',               110000,   55000,  75, 20, 'DEP-BAL-009',  0.450, 'D-01-01', '2025-09-20 16:00:00', TRUE, 4, 5),
(10, 'Mancuernas 10kg Par',       'Par de mancuernas con caucho',             260000,  160000,  30, 15, 'DEP-MAN-010', 20.000, 'D-01-02', '2025-09-20 16:10:00', TRUE, 4, 5),
(11, 'Novela El Ultimo Viaje',    'Novela de 320 paginas',                     45000,   20000,  50, 20, 'LIB-NOV-011',  0.400, 'E-01-01', '2025-10-01 09:00:00', TRUE, 5, 5);

-- --------------------------- clientes --------------------------------
INSERT INTO clientes
    (id_cliente, nombre, apellido, email, contrasena, direccion_envio,
     fecha_nacimiento, fecha_registro) VALUES
(1, 'Andres',   'Cardenas', 'andres.cardenas@correo.com', '$2y$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'Cra 27 #45-12, Bucaramanga',        '1991-03-22', '2025-09-12 09:14:00'),
(2, 'Laura',    'Mejia',    'laura.mejia@correo.com',     '$2y$10$mR4fV8sTqZ1nXc7dPwEuLeYb3kJhGvNaQxCzRtUiOpAsDfGhJkLmN', 'Calle 93 #11-27, Bogota',           '1988-11-05', '2025-09-25 17:42:00'),
(3, 'Carlos',   'Rueda',    'carlos.rueda@correo.com',    '$2y$10$aB1cD2eF3gH4iJ5kL6mN7oP8qR9sT0uV1wX2yZ3aB4cD5eF6gH7iJ', 'Cra 43A #18-95, Medellin',          '1995-07-14', '2025-11-02 12:03:00'),
(4, 'Diana',    'Ospina',   'diana.ospina@correo.com',    '$2y$10$kL9mN8oP7qR6sT5uV4wX3yZ2aB1cD0eF9gH8iJ7kL6mN5oP4qR3sT', 'Calle 36 #22-40, Piedecuesta',      '2000-01-30', '2025-12-18 08:27:00'),
(5, 'Julian',   'Barrera',  'julian.barrera@correo.com',  '$2y$10$zY9xW8vU7tS6rQ5pO4nM3lK2jI1hG0fE9dC8bA7zY6xW5vU4tS3rQ', 'Av Quebradaseca #15-33, Bucaramanga','1983-06-09', '2026-01-22 19:55:00'),
(6, 'Paola',    'Guerrero', 'paola.guerrero@correo.com',  '$2y$10$qW2eR3tY4uI5oP6aS7dF8gH9jK0lZ1xC2vB3nM4qW5eR6tY7uI8oP', 'Calle 100 #19-54, Bogota',          '1997-09-18', '2026-03-14 10:31:00'),
(7, 'Mauricio', 'Pineda',   'mauricio.pineda@correo.com', '$2y$10$lP0oI9uY8tR7eW6qA5sD4fG3hJ2kL1zX0cV9bN8mQ7wE6rT5yU4iO', 'Cra 70 #44-21, Medellin',           '1979-12-02', '2026-05-08 21:12:00'),
(8, 'Sofia',    'Valencia', 'sofia.valencia@correo.com',  '$2y$10$hG7fD6sA5pO4iU3yT2rE1wQ0zX9cV8bN7mK6jH5gF4dS3aP2oI1uY', 'Cra 33 #52-18, Floridablanca',      '1993-04-27', '2026-07-19 15:47:00');

-- ----------------------------- ventas --------------------------------
INSERT INTO ventas (id_venta, id_cliente, fecha_venta, estado) VALUES
( 1, 1, '2025-10-14 10:23:00', 'Entregado'),
( 2, 2, '2025-11-03 15:40:00', 'Entregado'),
( 3, 1, '2025-11-28 09:05:00', 'Entregado'),
( 4, 3, '2025-12-15 20:11:00', 'Entregado'),
( 5, 4, '2026-01-09 11:47:00', 'Entregado'),
( 6, 2, '2026-02-20 16:30:00', 'Entregado'),
( 7, 5, '2026-04-05 19:22:00', 'Enviado'),
( 8, 6, '2026-06-18 13:15:00', 'Entregado'),
( 9, 1, '2026-08-02 21:50:00', 'Procesando'),
(10, 7, '2026-09-05 08:35:00', 'Cancelado');

-- ------------------------- detalle_ventas ----------------------------
INSERT INTO detalle_ventas (id_venta, id_producto, cantidad, precio_unitario_congelado) VALUES
( 1,  1, 1, 3100000),
( 1,  2, 2,   85000),
( 2,  5, 3,   55000),
( 2,  6, 1,  145000),
( 3,  3, 1,  320000),
( 3,  4, 1,  240000),
( 4,  7, 1,  480000),
( 4,  8, 2,  190000),
( 5,  9, 2,  110000),
( 5, 10, 1,  260000),
( 6,  1, 1, 3200000),
( 7,  2, 1,   85000),
( 7,  3, 2,  320000),
( 8,  5, 2,   55000),
( 8,  9, 1,  110000),
( 8,  2, 1,   85000),
( 9,  7, 1,  480000),
( 9,  4, 2,  240000),
(10,  6, 2,  145000);

-- --------------------------- promociones -----------------------------
-- Dos vencidas y una vigente, para que evt_deactivate_expired_promotions_hourly
-- tenga algo que desactivar en su primera corrida.
INSERT INTO promociones (codigo, descripcion, porcentaje, fecha_inicio, fecha_fin, activa) VALUES
('BLACK2025',   'Black Friday 2025',            25.00, '2025-11-24 00:00:00', '2025-11-30 23:59:59', TRUE),
('NAVIDAD2025', 'Temporada navidena 2025',      15.00, '2025-12-01 00:00:00', '2025-12-26 23:59:59', TRUE),
('BIENVENIDA',  'Descuento primera compra',     10.00, '2025-09-01 00:00:00', '2027-12-31 23:59:59', TRUE);


-- =====================================================================
-- SECCION 5: CONSOLIDACION DE VALORES CALCULADOS
--
-- Estos campos se mantienen al dia con triggers (archivo 05), pero los
-- datos de ejemplo se cargan de forma masiva, asi que hay que
-- calcularlos una vez aqui.
-- =====================================================================

-- total de cada venta = suma de sus lineas de detalle
UPDATE ventas v
SET v.total = (
    SELECT IFNULL(SUM(d.cantidad * d.precio_unitario_congelado), 0)
    FROM detalle_ventas d
    WHERE d.id_venta = v.id_venta
);

-- gasto historico acumulado de cada cliente (sin contar ventas canceladas)
UPDATE clientes c
SET c.total_gastado = (
    SELECT IFNULL(SUM(v.total), 0)
    FROM ventas v
    WHERE v.id_cliente = c.id_cliente
      AND v.estado <> 'Cancelado'
);

-- fecha del ultimo pedido de cada cliente
UPDATE clientes c
SET c.fecha_ultimo_pedido = (
    SELECT MAX(v.fecha_venta)
    FROM ventas v
    WHERE v.id_cliente = c.id_cliente
);


-- =====================================================================
-- SECCION 6: VERIFICACION
-- =====================================================================

SELECT 'categorias' AS tabla, COUNT(*) AS filas FROM categorias
UNION ALL SELECT 'proveedores',    COUNT(*) FROM proveedores
UNION ALL SELECT 'productos',      COUNT(*) FROM productos
UNION ALL SELECT 'clientes',       COUNT(*) FROM clientes
UNION ALL SELECT 'ventas',         COUNT(*) FROM ventas
UNION ALL SELECT 'detalle_ventas', COUNT(*) FROM detalle_ventas
UNION ALL SELECT 'promociones',    COUNT(*) FROM promociones;

SELECT v.id_venta,
       CONCAT(c.nombre, ' ', c.apellido) AS cliente,
       v.fecha_venta,
       v.estado,
       v.total
FROM ventas v
JOIN clientes c ON c.id_cliente = v.id_cliente
ORDER BY v.fecha_venta;
