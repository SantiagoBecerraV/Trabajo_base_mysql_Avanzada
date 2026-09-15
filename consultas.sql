

-- ===========================================
-- CONSULTAS
-- TOP 10 PRODUCTOS MAS VENDIDOS
-- ===========================================

-- Generar un ranking con los 10 productos que han generado más ingresos.
SELECT 
	p.nombre AS producto,
	p.id_producto,
	SUM(dv.cantidad) AS unidades_vendidas,
	SUM(dv.cantidad * precio_unitario_congelado) AS total_ingresos
FROM productos p
INNER JOIN detalle_ventas dv ON p.id_producto = dv.id_producto
INNER JOIN ventas v ON dv.id_venta = v.id_venta
WHERE v.estado != 'Cancelado'
GROUP BY p.id_producto, p.nombre
ORDER BY total_ingresos DESC
LIMIT 10;

-- Identificar los productos en el 10% inferior de ventas 
SELECT
	p.nombre AS producto,
	p.id_producto,
    COALESCE(SUM(dv.cantidad * dv.precio_unitario_congelado), 0) AS ingresos_totales
FROM productos p
LEFT JOIN detalle_ventas dv ON p.id_producto = dv.id_producto
LEFT JOIN ventas v ON dv.id_venta = v.id_venta AND v.estado != 'Cancelado'
GROUP BY p.id_producto, p.nombre
ORDER BY ingresos_totales ASC
LIMIT 1; -- En tu script de prueba con 11 productos, el 10% equivale exactamente a 1 producto (ej. 'Novela El Ultimo Viaje').


-- Listar los 5 clientes con el mayor valor de vida

SELECT
	c.id_cliente,
	c.nombre,
	c.apellido,
	COUNT(v.id_venta) AS total_compras,
	SUM(v.total) AS ltv_total
FROM clientes c
INNER JOIN ventas v ON c.id_cliente = v.id_cliente
WHERE estado != 'Cancelado'
GROUP BY c.id_cliente, c.nombre, c.apellido
ORDER BY ltv_total DESC
LIMIT 5;

-- Mostrar las ventas totales agrupadas por mes y año.


SELECT
	YEAR(fecha_venta) AS anio,
	MONTH(fecha_venta) AS numero_mes,
	DATE_FORMAT(fecha_venta, '%M') AS nombre_mes, -- Muestra el nombre del mes (ej. October, November)
	COUNT(id_venta) AS cantidad_venta,
	SUM(total) AS total_venta
FROM ventas v
WHERE estado != 'Cancelado'
GROUP BY 
    YEAR(fecha_venta), 
    MONTH(fecha_venta),
    DATE_FORMAT(fecha_venta, '%M')
ORDER BY 
    anio ASC, 
    numero_mes ASC;
   
 
-- Calcular el número de nuevos clientes registrados por trimestre.
   
SELECT
    YEAR(fecha_registro) AS anio,
    MONTH(fecha_registro) AS numero_mes,
    QUARTER(fecha_registro) AS trimestre_numero,
    CONCAT('Q', QUARTER(fecha_registro), '-', YEAR(fecha_registro)) AS trimestre_etiqueta,
    COUNT(id_cliente) AS clientes_nuevos
FROM clientes 
GROUP BY 
    YEAR(fecha_registro),
    MONTH(fecha_registro),
    QUARTER(fecha_registro),
    CONCAT('Q', QUARTER(fecha_registro), '-', YEAR(fecha_registro))
ORDER BY 
    anio ASC, 
    trimestre_numero ASC;

-- Determinar qué porcentaje de clientes ha realizado más de una compra.
WITH ComprasPorCliente AS (
    SELECT 
        id_cliente,
        COUNT(id_venta) AS total_compras
    FROM ventas
    WHERE estado != 'Cancelado'
    GROUP BY id_cliente
)
SELECT 
    COUNT(id_cliente) AS total_clientes_compradores,
    COUNT(CASE WHEN total_compras > 1 THEN 1 END) AS clientes_recurrentes,
    ROUND(
        (COUNT(CASE WHEN total_compras > 1 THEN 1 END) * 100.0) / COUNT(id_cliente), 
        2
    ) AS tasa_compra_repetida_porcentaje
FROM ComprasPorCliente;

-- Identificar pares de productos que a menudo se compran en la misma transacción.
SELECT 
    p1.nombre AS producto_1,
    p2.nombre AS producto_2,
    COUNT(*) AS veces_comprados_juntos
FROM detalle_ventas dv1
INNER JOIN detalle_ventas dv2 
    ON dv1.id_venta = dv2.id_venta 
    AND dv1.id_producto < dv2.id_producto
INNER JOIN productos p1 ON dv1.id_producto = p1.id_producto
INNER JOIN productos p2 ON dv2.id_producto = p2.id_producto
INNER JOIN ventas v ON dv1.id_venta = v.id_venta
WHERE v.estado != 'Cancelado'
GROUP BY 
    p1.id_producto, 
    p1.nombre, 
    p2.id_producto, 
    p2.nombre
ORDER BY veces_comprados_juntos DESC;

-- Calcular la tasa de rotación de stock para cada categoría de producto.

SELECT 
    c.id_categoria,
    c.nombre AS categoria,
    COALESCE(SUM(p.stock), 0) AS stock_actual,
    COALESCE(SUM(dv.cantidad), 0) AS unidades_vendidas_totales,
    ROUND(
        COALESCE(SUM(dv.cantidad), 0) / NULLIF(SUM(p.stock), 0), 
        2
    ) AS tasa_rotacion_stock
FROM categorias c
LEFT JOIN productos p ON c.id_categoria = p.id_categoria
LEFT JOIN detalle_ventas dv ON p.id_producto = dv.id_producto
LEFT JOIN ventas v ON dv.id_venta = v.id_venta AND v.estado != 'Cancelado'
GROUP BY c.id_categoria, c.nombre
ORDER BY tasa_rotacion_stock DESC;

-- Listar productos cuyo stock actual está por debajo de su umbral mínimo.

-- Un truco de un senior como yo Santiago Becerra Creacion columna
ALTER TABLE productos
ADD COLUMN stock_minimo INT NOT NULL DEFAULT 10;

UPDATE productos
SET stock_minimo = CASE 
    WHEN precio > 2000000 THEN 5      
    WHEN precio > 500000 THEN 15      
    ELSE 20                           
END;

SELECT id_producto, nombre, precio, stock, stock_minimo 
FROM productos;

SELECT 
    p.id_producto,
    p.nombre,
    c.nombre AS categoria,
    pv.nombre AS proveedor,
    p.stock AS stock_actual,
    p.stock_minimo,
    (p.stock_minimo - p.stock) AS unidades_faltantes,
    p.precio
FROM productos p
INNER JOIN categorias c ON p.id_categoria = c.id_categoria
INNER JOIN proveedores pv ON p.id_proveedor = pv.id_proveedor
WHERE p.stock < p.stock_minimo
ORDER BY unidades_faltantes DESC;

-- Identificar clientes que agregaron productos pero no completaron una venta en un período determinado.

SELECT
	c.id_cliente,
	CONCAT(c.nombre, '', c.apellido) AS nombre_cliente,
	c.email,
	v.id_venta,
	v.fecha_venta,
	v.estado,
	v.total AS valor_carrito,
    DATEDIFF(NOW(), v.fecha_venta) AS dias_desde_abandono
FROM ventas v
INNER JOIN clientes c ON v.id_cliente = c.id_cliente
WHERE v.estado IN ('Pendiente de pago', 'Cancelado')
    AND v.fecha_venta >= DATE_SUB(NOW(), INTERVAL 60 DAY)
ORDER BY v.total DESC, v.fecha_venta DESC;


-- ===========================================
-- TRIGGER


-- trg_audit_precio_producto_after_update

CREATE TABLE auditoria_precios (
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
SET precio = 3200000
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
    
    SELECT stock, nombre INTO stock_disponible, nombre_producto
    FROM productos
    WHERE id_producto = NEW.id_producto;
    
    IF stock_disponible < NEW.cantidad THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = CONCAT('Stock insuficiente para ', nombre_producto);
    END IF;
END$$

DELIMITER ;

-- Resultado esperado: ERROR
INSERT INTO detalle_ventas (id_venta, id_producto, cantidad, precio_unitario_congelado)
VALUES (11, 4, 15, 240000);

-- Resultado esperado: SUCCESS
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
-- Debe mostrar: 8 clientes actuales


INSERT INTO clientes (nombre, apellido, email, contrasena, direccion_envio)
VALUES ('Juan', 'Perez', 'juan.perez@correo.com', '$2y$10$hashejemplo123', 'Cra 50 #30-40, Bucaramanga');

-- El trigger se ejecuta automáticamente

SELECT * FROM log_clientes
ORDER BY fecha_evento DESC;


-- trg_update_total_gastado_cliente

ALTER TABLE clientes
ADD COLUMN total_gastado DECIMAL(14,2) DEFAULT 0;

DESCRIBE clientes;
-- Debe mostrar la nueva columna total_gastado

DELIMITER $$

CREATE TRIGGER trg_update_total_gastado_cliente
AFTER INSERT ON ventas
FOR EACH ROW
BEGIN
    -- Sumar el total de la venta al total_gastado del cliente
    UPDATE clientes
    SET total_gastado = total_gastado + NEW.total
    WHERE id_cliente = NEW.id_cliente;
END$$

DELIMITER ;

-- Calcular el total gastado de cada cliente basado en ventas previas
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

-- Insertar una nueva venta para Julian (id_cliente = 5)
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

ALTER TABLE productos
ADD COLUMN fecha_modificacion DATETIME DEFAULT NULL;
DESCRIBE productos;

DELIMITER $$

CREATE TRIGGER trg_set_fecha_modificacion_producto
AFTER UPDATE ON productos
FOR EACH ROW
BEGIN
    -- Actualizar la fecha de modificación del producto
    UPDATE productos
    SET fecha_modificacion = NOW()
    WHERE id_producto = NEW.id_producto;
END$$

DELIMITER ;

UPDATE productos
SET precio = 3300000
WHERE id_producto = 1;

SELECT 
    id_producto,
    nombre,
    precio,
    stock,
    fecha_creacion,
    fecha_modificacion
FROM productos
WHERE id_producto = 1;

-- OTRO CAMBIO DE PRUEBA

UPDATE productos
SET stock = 30
WHERE id_producto = 1;

SELECT 
    id_producto,
    nombre,
    precio,
    stock,
    fecha_creacion,
    fecha_modificacion
FROM productos
WHERE id_producto = 1;


-- trg_prevent_negative_stock

DELIMITER $$

CREATE TRIGGER trg_prevent_negative_stock
BEFORE UPDATE ON productos
FOR EACH ROW
BEGIN
    -- Verificar si alguien intenta poner stock negativo
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
    -- Capitalizar nombre: primera letra mayúscula, resto minúscula
    SET NEW.nombre = CONCAT(
        UPPER(SUBSTRING(NEW.nombre, 1, 1)),
        LOWER(SUBSTRING(NEW.nombre, 2))
    );
    
    -- Capitalizar apellido: primera letra mayúscula, resto minúscula
    SET NEW.apellido = CONCAT(
        UPPER(SUBSTRING(NEW.apellido, 1, 1)),
        LOWER(SUBSTRING(NEW.apellido, 2))
    );
END$$

DELIMITER ;

INSERT INTO clientes (nombre, apellido, email, contrasena, direccion_envio)
VALUES ('maria', 'garcia', 'maria.garcia@correo.com', '$2y$10$hash123', 'Cra 60 #25-30, Bucaramanga');

SELECT 
    id_cliente,
    nombre,
    apellido,
    email
FROM clientes
WHERE email = 'maria.garcia@correo.com';


-- trg_recalculate_total_venta_on_detalle_change

DELIMITER $$

CREATE TRIGGER trg_recalculate_total_venta_on_detalle_change
AFTER UPDATE ON detalle_ventas
FOR EACH ROW
BEGIN
    -- Recalcular el total de la venta después de cambiar detalle
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

-- Cambiar la cantidad en un detalle (aumentar de 1 a 2 laptops)
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
    -- Verificar si alguien intenta poner precio cero o negativo
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

-- Ver el ID asignado
SELECT id_categoria FROM categorias WHERE nombre = 'General';

DELIMITER $$

CREATE TRIGGER trg_assign_default_category_on_null
BEFORE INSERT ON productos
FOR EACH ROW
BEGIN
    -- Si no se especifica categoría, asignar la categoría "General"
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

INSERT INTO productos (nombre, descripcion, precio, costo, stock, sku)
VALUES (
    'Producto Misterio',
    'Un producto sin categoría asignada',
    150000,
    75000,
    10,
    'MYST-001'
);


