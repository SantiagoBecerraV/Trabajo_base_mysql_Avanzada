-- =====================================================================
-- PROYECTO BASE DE DATOS AVANZADA - E-COMMERCE
-- Archivo 03: Funciones Definidas por el Usuario (UDF)
--
-- Requisito previo: haber ejecutado 01_Esquema_y_Datos.sql
-- =====================================================================

USE ecommerce_db;

DELIMITER $$

-- =====================================================================
-- 1. fn_CalcularTotalVenta
--    Calcula el monto total de una venta sumando sus lineas de detalle.
--    Devuelve 0 si la venta no existe o no tiene detalle.
-- =====================================================================
DROP FUNCTION IF EXISTS fn_CalcularTotalVenta$$
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
END$$


-- =====================================================================
-- 2. fn_VerificarDisponibilidadStock
--    Valida si hay stock suficiente de un producto para una cantidad.
--    Devuelve FALSE si el producto no existe.
-- =====================================================================
DROP FUNCTION IF EXISTS fn_VerificarDisponibilidadStock$$
CREATE FUNCTION fn_VerificarDisponibilidadStock(p_id_producto INT, p_cantidad INT)
RETURNS BOOLEAN
READS SQL DATA
BEGIN
    DECLARE v_stock INT;

    SELECT stock
      INTO v_stock
      FROM productos
     WHERE id_producto = p_id_producto;

    RETURN IFNULL(v_stock, -1) >= p_cantidad;
END$$


-- =====================================================================
-- 3. fn_ObtenerPrecioProducto
--    Devuelve el precio de lista actual de un producto.
--    No confundir con precio_unitario_congelado, que es el precio
--    historico guardado en cada linea de venta.
-- =====================================================================
DROP FUNCTION IF EXISTS fn_ObtenerPrecioProducto$$
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
END$$


-- =====================================================================
-- 4. fn_CalcularEdadCliente
--    Calcula la edad en anios cumplidos a partir de fecha_nacimiento.
--    Devuelve NULL si el cliente no registro su fecha de nacimiento.
-- =====================================================================
DROP FUNCTION IF EXISTS fn_CalcularEdadCliente$$
CREATE FUNCTION fn_CalcularEdadCliente(p_id_cliente INT)
RETURNS INT
READS SQL DATA
BEGIN
    DECLARE v_fecha_nac DATE;

    SELECT fecha_nacimiento
      INTO v_fecha_nac
      FROM clientes
     WHERE id_cliente = p_id_cliente;

    IF v_fecha_nac IS NULL THEN
        RETURN NULL;
    END IF;

    RETURN TIMESTAMPDIFF(YEAR, v_fecha_nac, CURDATE());
END$$


-- =====================================================================
-- 5. fn_FormatearNombreCompleto
--    Devuelve "Apellido, Nombre" con capitalizacion normalizada,
--    que es el formato estandar para listados y reportes.
-- =====================================================================
DROP FUNCTION IF EXISTS fn_FormatearNombreCompleto$$
CREATE FUNCTION fn_FormatearNombreCompleto(p_id_cliente INT)
RETURNS VARCHAR(170)
READS SQL DATA
BEGIN
    DECLARE v_nombre   VARCHAR(80);
    DECLARE v_apellido VARCHAR(80);

    SELECT nombre, apellido
      INTO v_nombre, v_apellido
      FROM clientes
     WHERE id_cliente = p_id_cliente;

    IF v_nombre IS NULL THEN
        RETURN NULL;
    END IF;

    RETURN CONCAT(
        UPPER(LEFT(v_apellido, 1)), LOWER(SUBSTRING(v_apellido, 2)),
        ', ',
        UPPER(LEFT(v_nombre, 1)),   LOWER(SUBSTRING(v_nombre, 2))
    );
END$$


-- =====================================================================
-- 6. fn_EsClienteNuevo
--    TRUE si el cliente hizo su PRIMERA compra en los ultimos 30 dias.
--    Un cliente sin compras no se considera nuevo: se considera
--    registrado pero no convertido.
-- =====================================================================
DROP FUNCTION IF EXISTS fn_EsClienteNuevo$$
CREATE FUNCTION fn_EsClienteNuevo(p_id_cliente INT)
RETURNS BOOLEAN
READS SQL DATA
BEGIN
    DECLARE v_primera_compra DATETIME;

    SELECT MIN(fecha_venta)
      INTO v_primera_compra
      FROM ventas
     WHERE id_cliente = p_id_cliente
       AND estado <> 'Cancelado';

    IF v_primera_compra IS NULL THEN
        RETURN FALSE;
    END IF;

    RETURN DATEDIFF(CURDATE(), v_primera_compra) <= 30;
END$$


-- =====================================================================
-- 7. fn_CalcularCostoEnvio
--    Costo de envio segun el peso total de los productos de la venta.
--    Tarifa: $2.000 por kilogramo, con un minimo de $5.000 por envio.
-- =====================================================================
DROP FUNCTION IF EXISTS fn_CalcularCostoEnvio$$
CREATE FUNCTION fn_CalcularCostoEnvio(p_id_venta INT)
RETURNS DECIMAL(12,2)
READS SQL DATA
BEGIN
    DECLARE v_peso_total DECIMAL(12,3);
    DECLARE v_costo      DECIMAL(12,2);

    SELECT SUM(p.peso_kg * d.cantidad)
      INTO v_peso_total
      FROM detalle_ventas d
      JOIN productos p ON p.id_producto = d.id_producto
     WHERE d.id_venta = p_id_venta;

    SET v_costo = IFNULL(v_peso_total, 0) * 2000;

    RETURN GREATEST(v_costo, 5000);
END$$


-- =====================================================================
-- 8. fn_AplicarDescuento
--    Aplica un porcentaje de descuento a un monto.
--    Es DETERMINISTIC porque no consulta tablas: para los mismos
--    argumentos siempre devuelve el mismo resultado.
-- =====================================================================
DROP FUNCTION IF EXISTS fn_AplicarDescuento$$
CREATE FUNCTION fn_AplicarDescuento(p_monto DECIMAL(14,2), p_porcentaje DECIMAL(5,2))
RETURNS DECIMAL(14,2)
DETERMINISTIC
BEGIN
    IF p_porcentaje IS NULL OR p_porcentaje <= 0 THEN
        RETURN p_monto;
    END IF;

    IF p_porcentaje >= 100 THEN
        RETURN 0;
    END IF;

    RETURN ROUND(p_monto - (p_monto * p_porcentaje / 100), 2);
END$$


-- =====================================================================
-- 9. fn_ObtenerUltimaFechaCompra
--    Fecha de la compra mas reciente de un cliente.
--    Devuelve NULL si el cliente nunca ha comprado.
-- =====================================================================
DROP FUNCTION IF EXISTS fn_ObtenerUltimaFechaCompra$$
CREATE FUNCTION fn_ObtenerUltimaFechaCompra(p_id_cliente INT)
RETURNS DATETIME
READS SQL DATA
BEGIN
    DECLARE v_ultima DATETIME;

    SELECT MAX(fecha_venta)
      INTO v_ultima
      FROM ventas
     WHERE id_cliente = p_id_cliente
       AND estado <> 'Cancelado';

    RETURN v_ultima;
END$$


-- =====================================================================
-- 10. fn_ValidarFormatoEmail
--     Comprueba el formato de una direccion de correo con una
--     expresion regular. Valida la FORMA, no la existencia del buzon.
-- =====================================================================
DROP FUNCTION IF EXISTS fn_ValidarFormatoEmail$$
CREATE FUNCTION fn_ValidarFormatoEmail(p_email VARCHAR(150))
RETURNS BOOLEAN
DETERMINISTIC
BEGIN
    IF p_email IS NULL THEN
        RETURN FALSE;
    END IF;

    RETURN p_email REGEXP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$';
END$$

DELIMITER ;


-- =====================================================================
-- PRUEBAS DE LAS 10 FUNCIONES
-- =====================================================================

SELECT 'fn_CalcularTotalVenta(1)'                        AS funcion, fn_CalcularTotalVenta(1)                        AS resultado
UNION ALL SELECT 'fn_VerificarDisponibilidadStock(4,10)',        fn_VerificarDisponibilidadStock(4, 10)
UNION ALL SELECT 'fn_VerificarDisponibilidadStock(4,5)',         fn_VerificarDisponibilidadStock(4, 5)
UNION ALL SELECT 'fn_ObtenerPrecioProducto(1)',                  fn_ObtenerPrecioProducto(1)
UNION ALL SELECT 'fn_CalcularEdadCliente(1)',                    fn_CalcularEdadCliente(1)
UNION ALL SELECT 'fn_EsClienteNuevo(1)',                         fn_EsClienteNuevo(1)
UNION ALL SELECT 'fn_CalcularCostoEnvio(1)',                     fn_CalcularCostoEnvio(1)
UNION ALL SELECT 'fn_AplicarDescuento(100000, 20)',              fn_AplicarDescuento(100000, 20)
UNION ALL SELECT 'fn_ValidarFormatoEmail(correo@ejemplo.com)',   fn_ValidarFormatoEmail('correo@ejemplo.com')
UNION ALL SELECT 'fn_ValidarFormatoEmail(correo-malo)',          fn_ValidarFormatoEmail('correo-malo');

SELECT fn_FormatearNombreCompleto(1)  AS nombre_formateado_cliente_1;
SELECT fn_ObtenerUltimaFechaCompra(1) AS ultima_compra_cliente_1;

-- Uso combinado: las funciones tambien sirven dentro de una consulta normal
SELECT
    c.id_cliente,
    fn_FormatearNombreCompleto(c.id_cliente)  AS cliente,
    fn_CalcularEdadCliente(c.id_cliente)      AS edad,
    fn_ObtenerUltimaFechaCompra(c.id_cliente) AS ultima_compra,
    fn_EsClienteNuevo(c.id_cliente)           AS es_nuevo
FROM clientes c
ORDER BY c.id_cliente;
