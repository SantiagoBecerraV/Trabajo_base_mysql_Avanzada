-- ===========================================
-- TRIGGER
USE ecommerce_db;


-- trg_audit_precio_producto_after_update

CREATE TABLE  IF NOT EXISTS auditoria_precios (
    id_auditoria INT AUTO_INCREMENT PRIMARY KEY,
    id_producto INT NOT NULL,
    nombre_producto VARCHAR(150),
    precio_anterior DECIMAL(12,2),
    precio_nuevo DECIMAL(12,2),
    diferencia DECIMAL(12,2),
    porcentaje_cambio DECIMAL(5,2),
    usuario VARCHAR(100) DEFAULT 'sistema',
    fecha_cambio DATETIME DEFAULT CURRENT_TIMESTAMP,
    razon_cambio VARCHAR(255),
    FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
);

DELIMITER $$

CREATE TRIGGER trg_audit_precio_producto_after_update
AFTER UPDATE ON productos
FOR EACH ROW
BEGIN
    -- Solo registra si el precio cambió
    IF OLD.precio != NEW.precio THEN
        INSERT INTO auditoria_precios (
            id_producto,
            nombre_producto,
            precio_anterior,
            precio_nuevo,
            diferencia,
            porcentaje_cambio,
            usuario,
            fecha_cambio
        ) VALUES (
            NEW.id_producto,
            NEW.nombre,
            OLD.precio,
            NEW.precio,
            (NEW.precio - OLD.precio),
            ROUND(((NEW.precio - OLD.precio) / OLD.precio * 100), 2),
            COALESCE(USER(), 'sistema'),
            NOW()
        );
    END IF;
END$$

DELIMITER ;

SHOW TRIGGERS FROM ecommerce_db;

SELECT id_producto, nombre, precio 
FROM productos 
WHERE id_producto = 1;

UPDATE productos
SET precio = 3500000
WHERE id_producto = 1;

SELECT * FROM auditoria_precios
ORDER BY fecha_cambio DESC;


-- trg_check_stock_before_insert_venta 


DELIMITER $$

CREATE TRIGGER trg_check_stock_before_insert_venta
BEFORE INSERT ON detalle_ventas
FOR EACH ROW
BEGIN
    DECLARE stock_disponible INT;
    DECLARE nombre_producto VARCHAR(150);
	DECLARE msj_error VARCHAR(255);

    SELECT stock, nombre INTO stock_disponible, nombre_producto
    FROM productos
    WHERE id_producto = NEW.id_producto;

    IF stock_disponible < NEW.cantidad THEN
        SET msj_error = CONCAT('Stock insuficiente para ', nombre_producto);
        
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = msj_error;
    END IF;
END$$
DELIMITER ;

-- Resultado esperado: ERROR
INSERT INTO detalle_ventas (id_venta, id_producto, cantidad, precio_unitario_congelado)
VALUES (11, 4, 15, 240000);

-- Resultado esperado: DEBE SERVIR
INSERT INTO detalle_ventas (id_venta, id_producto, cantidad, precio_unitario_congelado)
VALUES (11, 2, 5, 85000);


-- trg_update_stock_after_insert_venta

DELIMITER $$

CREATE TRIGGER trg_update_stock_after_insert_venta
AFTER INSERT ON detalle_ventas
FOR EACH ROW
BEGIN

	UPDATE productos
    SET stock = stock - NEW.cantidad
    WHERE id_producto = NEW.id_producto;
END$$

DELIMITER ;

-- stock antes
SELECT id_producto, nombre, stock 
FROM productos 
WHERE id_producto = 2;

-- Hacer venta
INSERT INTO detalle_ventas (id_venta, id_producto, cantidad, precio_unitario_congelado)
VALUES (11, 2, 10, 85000);

-- stock despues
SELECT id_producto, nombre, stock 
FROM productos 
WHERE id_producto = 2;


-- trg_prevent_delete_categoria_with_products

DELIMITER $$

CREATE TRIGGER trg_prevent_delete_categoria_with_products
BEFORE DELETE ON categorias
FOR EACH ROW
BEGIN
    DECLARE cantidad_productos INT;
    
    SELECT COUNT(*) INTO cantidad_productos
    FROM productos
    WHERE id_categoria = OLD.id_categoria;
    
    IF cantidad_productos > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'No se puede eliminar esta categoria porque tiene productos asociados';
    END IF;
END$$

DELIMITER ;

-- ver productosd por categoria

SELECT 
    c.id_categoria,
    c.nombre AS categoria,
    COUNT(p.id_producto) AS cantidad_productos
FROM categorias c
LEFT JOIN productos p ON c.id_categoria = p.id_categoria
GROUP BY c.id_categoria, c.nombre;

-- Intentar eliminar
DELETE FROM categorias WHERE id_categoria = 1;

INSERT INTO categorias (nombre, descripcion)
VALUES ('Juguetes', 'Articulos para niños');

-- Se elimina
DELETE FROM categorias WHERE id_categoria = 6;


-- 	trg_log_new_customer_after_insert

CREATE TABLE log_clientes (
    id_log INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente INT NOT NULL,
    nombre VARCHAR(80),
    apellido VARCHAR(80),
    email VARCHAR(150),
    accion VARCHAR(50),
    fecha_evento DATETIME DEFAULT CURRENT_TIMESTAMP,
    ip_origen VARCHAR(45),
    detalles TEXT,
    FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente)
);

DELIMITER $$

CREATE TRIGGER trg_log_new_customer_after_insert
AFTER INSERT ON clientes
FOR EACH ROW
BEGIN
    -- Registrar el nuevo cliente en el log
    INSERT INTO log_clientes (
        id_cliente,
        nombre,
        apellido,
        email,
        accion,
        fecha_evento,
        detalles
    ) VALUES (
        NEW.id_cliente,
        NEW.nombre,
        NEW.apellido,
        NEW.email,
        'REGISTRO',
        NOW(),
        CONCAT('Nuevo cliente registrado. Dirección: ', NEW.direccion_envio)
    );
END$$

DELIMITER ;


SELECT COUNT(*) AS total_clientes FROM clientes;
-- Debe mostrar la cantidad actual


INSERT INTO clientes (nombre, apellido, email, contrasena, direccion_envio)
VALUES ('Juanjo', 'Sanchez', 'juan.san@correo.com', '$2y$10$hashejemplo123', 'Cra 50 #30-40, Bucaramanga');


SELECT * FROM log_clientes
ORDER BY fecha_evento DESC;



-- trg_update_total_gastado_cliente

ALTER TABLE clientes
ADD COLUMN total_gastado DECIMAL(14,2) DEFAULT 0;

DESCRIBE clientes;

DELIMITER $$

CREATE TRIGGER trg_update_total_gastado_cliente
AFTER INSERT ON ventas
FOR EACH ROW
BEGIN
    -- Sumar el total
    UPDATE clientes
    SET total_gastado = total_gastado + NEW.total
    WHERE id_cliente = NEW.id_cliente;
END$$

DELIMITER ;

-- Calcular el total gastado 
UPDATE clientes c
SET total_gastado = (
    SELECT COALESCE(SUM(v.total), 0)
    FROM ventas v
    WHERE v.id_cliente = c.id_cliente
);

-- Ver el resultado
SELECT 
    id_cliente,
    CONCAT(nombre, ' ', apellido) AS nombre_completo,
    total_gastado
FROM clientes
ORDER BY total_gastado DESC;

-- Insertar una nueva venta para Julian
INSERT INTO ventas (id_cliente, estado, total)
VALUES (5, 'Pendiente de Pago', 500000);


SELECT 
    id_cliente,
    CONCAT(nombre, ' ', apellido) AS nombre_completo,
    email,
    total_gastado
FROM clientes
WHERE id_cliente = 5;


-- trg_set_fecha_modificacion_producto

CREATE TABLE IF NOT EXISTS log_fecha_modificacion (
    id_log INT AUTO_INCREMENT PRIMARY KEY,
    id_producto INT NOT NULL,
    fecha_modificacion DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
);

DELIMITER $$

CREATE TRIGGER trg_set_fecha_modificacion_producto
AFTER UPDATE ON productos
FOR EACH ROW
BEGIN
    INSERT INTO log_fecha_modificacion (id_producto, fecha_modificacion)
    VALUES (NEW.id_producto, NOW());
END$$

DELIMITER ;

SELECT * FROM log_fecha_modificacion;

UPDATE productos
SET precio = 420000
WHERE id_producto = 3;

SELECT * FROM log_fecha_modificacion
ORDER BY fecha_modificacion DESC
LIMIT 1;


-- trg_prevent_negative_stock

DELIMITER $$

CREATE TRIGGER trg_prevent_negative_stock
BEFORE UPDATE ON productos
FOR EACH ROW
BEGIN
    IF NEW.stock < 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: El stock no puede ser negativo. Valor rechazado.';
    END IF;
END$$

DELIMITER ;

SELECT 
    id_producto,
    nombre,
    stock
FROM productos
WHERE id_producto = 2;

-- Resultado: ERROR
UPDATE productos
SET stock = -50
WHERE id_producto = 2;

SELECT 
    id_producto,
    nombre,
    stock
FROM productos
WHERE id_producto = 2;


-- trg_capitalize_nombre_cliente

DELIMITER $$

CREATE TRIGGER trg_capitalize_nombre_cliente
BEFORE INSERT ON clientes
FOR EACH ROW
BEGIN
    SET NEW.nombre = CONCAT(
        UPPER(SUBSTRING(NEW.nombre, 1, 1)),
        LOWER(SUBSTRING(NEW.nombre, 2))
    );
    
    SET NEW.apellido = CONCAT(
        UPPER(SUBSTRING(NEW.apellido, 1, 1)),
        LOWER(SUBSTRING(NEW.apellido, 2))
    );
END$$

DELIMITER ;

INSERT INTO clientes (nombre, apellido, email, contrasena, direccion_envio)
VALUES ('cristian', 'NOCHEs', 'america.delab@correo.com', 'agtladelbucaros', 'Cra 60 #25-30, Cali');

SELECT 
    id_cliente,
    nombre,
    apellido,
    email
FROM clientes
WHERE email = 'america.delab@correo.com';


-- trg_recalculate_total_venta_on_detalle_change

DELIMITER $$

CREATE TRIGGER trg_recalculate_total_venta_on_detalle_change
AFTER UPDATE ON detalle_ventas
FOR EACH ROW
BEGIN
    UPDATE ventas
    SET total = (
        SELECT SUM(cantidad * precio_unitario_congelado)
        FROM detalle_ventas
        WHERE id_venta = NEW.id_venta
    )
    WHERE id_venta = NEW.id_venta;
END$$

DELIMITER ;

-- Ver la venta 1 y su total
SELECT 
    v.id_venta,
    c.nombre,
    c.apellido,
    v.fecha_venta,
    v.total AS total_venta
FROM ventas v
JOIN clientes c ON v.id_cliente = c.id_cliente
WHERE v.id_venta = 1;

SELECT 
    dv.id_detalle,
    dv.id_venta,
    p.nombre,
    dv.cantidad,
    dv.precio_unitario_congelado,
    (dv.cantidad * dv.precio_unitario_congelado) AS subtotal
FROM detalle_ventas dv
JOIN productos p ON dv.id_producto = p.id_producto
WHERE dv.id_venta = 1;

-- aumentar de 1 a 2 laptops
UPDATE detalle_ventas
SET cantidad = 2
WHERE id_detalle = 1;

SELECT 
    v.id_venta,
    c.nombre,
    c.apellido,
    v.fecha_venta,
    v.total AS total_venta
FROM ventas v
JOIN clientes c ON v.id_cliente = c.id_cliente
WHERE v.id_venta = 1;


-- trg_prevent_price_zero_or_less

DELIMITER $$

CREATE TRIGGER trg_prevent_price_zero_or_less
BEFORE UPDATE ON productos
FOR EACH ROW
BEGIN
    -- Verificar precio cero  
    IF NEW.precio <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: El precio debe ser mayor a cero. No se puede establecer precio cero o negativo.';
    END IF;
END$$

DELIMITER ;

SELECT 
    id_producto,
    nombre,
    precio,
    costo
FROM productos
WHERE id_producto = 1;

UPDATE productos
SET precio = 0
WHERE id_producto = 1;

-- Resultado: ERROR

UPDATE productos
SET precio = -100000
WHERE id_producto = 1;

-- Resultado: ERROR

SELECT 
    id_producto,
    nombre,
    precio
FROM productos
WHERE id_producto = 1;

-- trg_assign_default_category_on_null

SELECT * FROM categorias WHERE nombre = 'General';
INSERT INTO categorias (nombre, descripcion)
SELECT 'General', 'Categoría por defecto para productos sin clasificación'
WHERE NOT EXISTS (SELECT 1 FROM categorias WHERE nombre = 'General');

SELECT id_categoria FROM categorias WHERE nombre = 'General';

DELIMITER $$

CREATE TRIGGER trg_assign_default_category_on_null
BEFORE INSERT ON productos
FOR EACH ROW
BEGIN
    IF NEW.id_categoria IS NULL THEN
        SET NEW.id_categoria = (
            SELECT id_categoria 
            FROM categorias 
            WHERE nombre = 'General'
            LIMIT 1
        );
    END IF;
END$$

DELIMITER ;


SELECT id_categoria, nombre FROM categorias;

INSERT INTO productos (nombre, descripcion, precio, costo, stock, sku, id_categoria, id_proveedor)
VALUES (
    'Producto Misterio',
    'Un producto sin categoría asignada',
    150000,
    75000,
    10,
    'MYST-001',
    NULL,  
    1
);


SELECT 
    p.id_producto,
    p.nombre,
    p.id_categoria,
    c.nombre AS categoria_asignada,
    p.precio,
    p.stock
FROM productos p
LEFT JOIN categorias c ON p.id_categoria = c.id_categoria
WHERE p.nombre = 'Producto Misterio';

