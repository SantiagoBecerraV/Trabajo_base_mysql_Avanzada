USE ecommerce_db;


-- fecha_nacimiento en clientes
SET @existe_col := (
    SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = 'ecommerce_db'
    AND TABLE_NAME = 'clientes'
    AND COLUMN_NAME = 'fecha_nacimiento'
);
SET @sql_col := IF(@existe_col = 0,
    'ALTER TABLE clientes ADD COLUMN fecha_nacimiento DATE NULL',
    'SELECT 1'
);
PREPARE stmt FROM @sql_col;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- peso_kg en productos
SET @existe_col := (
    SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = 'ecommerce_db'
    AND TABLE_NAME = 'productos'
    AND COLUMN_NAME = 'peso_kg'
);
SET @sql_col := IF(@existe_col = 0,
    'ALTER TABLE productos ADD COLUMN peso_kg DECIMAL(8,3) NOT NULL DEFAULT 0',
    'SELECT 1'
);
PREPARE stmt FROM @sql_col;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- le ponemos fecha de nacimiento a los clientes para poder probar la funcion de edad
UPDATE clientes SET fecha_nacimiento = '1991-03-22' WHERE id_cliente = 1;
UPDATE clientes SET fecha_nacimiento = '1988-11-05' WHERE id_cliente = 2;
UPDATE clientes SET fecha_nacimiento = '1995-07-14' WHERE id_cliente = 3;
UPDATE clientes SET fecha_nacimiento = '2000-01-30' WHERE id_cliente = 4;
UPDATE clientes SET fecha_nacimiento = '1983-06-09' WHERE id_cliente = 5;
UPDATE clientes SET fecha_nacimiento = '1997-09-18' WHERE id_cliente = 6;
UPDATE clientes SET fecha_nacimiento = '1979-12-02' WHERE id_cliente = 7;
UPDATE clientes SET fecha_nacimiento = '1993-04-27' WHERE id_cliente = 8;

-- le ponemos peso a los productos para poder probar la funcion de envio
UPDATE productos SET peso_kg = 1.6   WHERE id_producto = 1;
UPDATE productos SET peso_kg = 0.12  WHERE id_producto = 2;
UPDATE productos SET peso_kg = 0.9   WHERE id_producto = 3;
UPDATE productos SET peso_kg = 0.3   WHERE id_producto = 4;
UPDATE productos SET peso_kg = 0.25  WHERE id_producto = 5;
UPDATE productos SET peso_kg = 0.7   WHERE id_producto = 6;
UPDATE productos SET peso_kg = 4.2   WHERE id_producto = 7;
UPDATE productos SET peso_kg = 1.8   WHERE id_producto = 8;
UPDATE productos SET peso_kg = 0.45  WHERE id_producto = 9;
UPDATE productos SET peso_kg = 20    WHERE id_producto = 10;
UPDATE productos SET peso_kg = 0.4   WHERE id_producto = 11;


-- ====================================
-- 1. fn_CalcularTotalVenta
-- suma el detalle de una venta y devuelve el total
-- ====================================
DROP FUNCTION IF EXISTS fn_CalcularTotalVenta;
CREATE FUNCTION fn_CalcularTotalVenta(p_id_venta INT)
RETURNS DECIMAL(14,2)
READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(14,2);

    SELECT SUM(cantidad * precio_unitario_congelado)
    INTO v_total
    FROM detalle_ventas
    WHERE id_venta = p_id_venta;

    RETURN IFNULL(v_total, 0);
END;


-- ====================================
-- 2. fn_VerificarDisponibilidadStock
-- revisa si hay suficiente stock de un producto para la cantidad pedida
-- ====================================
DROP FUNCTION IF EXISTS fn_VerificarDisponibilidadStock;
CREATE FUNCTION fn_VerificarDisponibilidadStock(p_id_producto INT, p_cantidad INT)
RETURNS BOOLEAN
READS SQL DATA
BEGIN
    DECLARE v_stock INT;

    SELECT stock
    INTO v_stock
    FROM productos
    WHERE id_producto = p_id_producto;

    IF v_stock >= p_cantidad THEN
        RETURN TRUE;
    ELSE
        RETURN FALSE;
    END IF;
END;


-- ====================================
-- 3. fn_ObtenerPrecioProducto
-- devuelve el precio actual de un producto (el de la tabla productos, no el congelado)
-- ====================================
DROP FUNCTION IF EXISTS fn_ObtenerPrecioProducto;
CREATE FUNCTION fn_ObtenerPrecioProducto(p_id_producto INT)
RETURNS DECIMAL(12,2)
READS SQL DATA
BEGIN
    DECLARE v_precio DECIMAL(12,2);

    SELECT precio
    INTO v_precio
    FROM productos
    WHERE id_producto = p_id_producto;

    RETURN v_precio;
END;


-- ====================================
-- 4. fn_CalcularEdadCliente
-- calcula la edad del cliente a partir de la fecha de nacimiento
-- ====================================
DROP FUNCTION IF EXISTS fn_CalcularEdadCliente;
CREATE FUNCTION fn_CalcularEdadCliente(p_id_cliente INT)
RETURNS INT
READS SQL DATA
BEGIN
    DECLARE v_fecha_nac DATE;
    DECLARE v_edad INT;

    SELECT fecha_nacimiento
    INTO v_fecha_nac
    FROM clientes
    WHERE id_cliente = p_id_cliente;

    SET v_edad = TIMESTAMPDIFF(YEAR, v_fecha_nac, CURDATE());

    RETURN v_edad;
END;


-- ====================================
-- 5. fn_FormatearNombreCompleto
-- junta nombre y apellido del cliente en un solo texto
-- ====================================
DROP FUNCTION IF EXISTS fn_FormatearNombreCompleto;
CREATE FUNCTION fn_FormatearNombreCompleto(p_id_cliente INT)
RETURNS VARCHAR(170)
READS SQL DATA
BEGIN
    DECLARE v_nombre VARCHAR(80);
    DECLARE v_apellido VARCHAR(80);

    SELECT nombre, apellido
    INTO v_nombre, v_apellido
    FROM clientes
    WHERE id_cliente = p_id_cliente;

    RETURN CONCAT(v_nombre, ' ', v_apellido);
END;


-- ====================================
-- 6. fn_EsClienteNuevo
-- dice si la primera compra del cliente fue hace menos de 30 dias
-- ====================================
DROP FUNCTION IF EXISTS fn_EsClienteNuevo;
CREATE FUNCTION fn_EsClienteNuevo(p_id_cliente INT)
RETURNS BOOLEAN
READS SQL DATA
BEGIN
    DECLARE v_primera_compra DATETIME;

    SELECT MIN(fecha_venta)
    INTO v_primera_compra
    FROM ventas
    WHERE id_cliente = p_id_cliente;

    IF v_primera_compra IS NULL THEN
        RETURN FALSE;
    END IF;

    IF DATEDIFF(CURDATE(), v_primera_compra) <= 30 THEN
        RETURN TRUE;
    ELSE
        RETURN FALSE;
    END IF;
END;


-- ====================================
-- 7. fn_CalcularCostoEnvio
-- suma el peso de los productos de una venta y calcula el envio
-- regla que usamos: $2000 por cada kilo, minimo $5000
-- ====================================
DROP FUNCTION IF EXISTS fn_CalcularCostoEnvio;
CREATE FUNCTION fn_CalcularCostoEnvio(p_id_venta INT)
RETURNS DECIMAL(12,2)
READS SQL DATA
BEGIN
    DECLARE v_peso_total DECIMAL(10,3);
    DECLARE v_costo DECIMAL(12,2);

    SELECT SUM(p.peso_kg * d.cantidad)
    INTO v_peso_total
    FROM detalle_ventas d
    JOIN productos p ON p.id_producto = d.id_producto
    WHERE d.id_venta = p_id_venta;

    SET v_costo = IFNULL(v_peso_total, 0) * 2000;

    IF v_costo < 5000 THEN
        SET v_costo = 5000;
    END IF;

    RETURN v_costo;
END;


-- ====================================
-- 8. fn_AplicarDescuento
-- resta un porcentaje de descuento a un monto
-- ====================================
DROP FUNCTION IF EXISTS fn_AplicarDescuento;
CREATE FUNCTION fn_AplicarDescuento(p_monto DECIMAL(14,2), p_porcentaje DECIMAL(5,2))
RETURNS DECIMAL(14,2)
DETERMINISTIC
BEGIN
    DECLARE v_resultado DECIMAL(14,2);

    SET v_resultado = p_monto - (p_monto * p_porcentaje / 100);

    RETURN v_resultado;
END;


-- ====================================
-- 9. fn_ObtenerUltimaFechaCompra
-- devuelve la fecha de la ultima venta que hizo un cliente
-- ====================================
DROP FUNCTION IF EXISTS fn_ObtenerUltimaFechaCompra;
CREATE FUNCTION fn_ObtenerUltimaFechaCompra(p_id_cliente INT)
RETURNS DATETIME
READS SQL DATA
BEGIN
    DECLARE v_ultima_fecha DATETIME;

    SELECT MAX(fecha_venta)
    INTO v_ultima_fecha
    FROM ventas
    WHERE id_cliente = p_id_cliente;

    RETURN v_ultima_fecha;
END;


-- ====================================
-- 10. fn_ValidarFormatoEmail
-- revisa con una expresion regular si el texto parece un correo valido
-- ====================================
DROP FUNCTION IF EXISTS fn_ValidarFormatoEmail;
CREATE FUNCTION fn_ValidarFormatoEmail(p_email VARCHAR(150))
RETURNS BOOLEAN
DETERMINISTIC
BEGIN
    IF p_email REGEXP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$' THEN
        RETURN TRUE;
    ELSE
        RETURN FALSE;
    END IF;
END;


-- ====================================
-- pruebas rapidas
-- ====================================
SELECT fn_CalcularTotalVenta(1) AS total_venta_1;
SELECT fn_VerificarDisponibilidadStock(4, 10) AS hay_stock_producto_4;
SELECT fn_ObtenerPrecioProducto(1) AS precio_producto_1;
SELECT fn_CalcularEdadCliente(1) AS edad_cliente_1;
SELECT fn_FormatearNombreCompleto(1) AS nombre_completo_cliente_1;
SELECT fn_EsClienteNuevo(8) AS cliente_8_es_nuevo;
SELECT fn_CalcularCostoEnvio(1) AS envio_venta_1;
SELECT fn_AplicarDescuento(100000, 20) AS con_descuento;
SELECT fn_ObtenerUltimaFechaCompra(1) AS ultima_compra_cliente_1;
SELECT fn_ValidarFormatoEmail('correo@ejemplo.com') AS email_valido;
