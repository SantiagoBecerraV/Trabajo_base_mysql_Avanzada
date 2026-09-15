-- =====================================================================
-- PROYECTO BASE DE DATOS AVANZADA - E-COMMERCE
-- Archivo 07: Procedimientos Almacenados
--
-- Requisitos previos: 01_Esquema_y_Datos.sql, 03_Funciones.sql
--                     y 05_Triggers.sql
-- =====================================================================

USE ecommerce_db;

DELIMITER $$

-- =====================================================================
-- 1. sp_RealizarNuevaVenta
--    Registra una venta completa de forma transaccional: valida stock,
--    crea el encabezado, inserta la linea de detalle y devuelve el id.
--
--    El EXIT HANDLER garantiza que si algo falla a mitad de camino se
--    deshace TODO. Sin el, podria quedar un encabezado de venta sin
--    detalle, que es justo la inconsistencia que busca el evento 10.
-- =====================================================================
DROP PROCEDURE IF EXISTS sp_RealizarNuevaVenta$$
CREATE PROCEDURE sp_RealizarNuevaVenta(
    IN  p_id_cliente  INT,
    IN  p_id_producto INT,
    IN  p_cantidad    INT,
    OUT p_id_venta    INT
)
BEGIN
    DECLARE v_stock  INT;
    DECLARE v_precio DECIMAL(12,2);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_id_venta = NULL;
        RESIGNAL;
    END;

    IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La cantidad debe ser mayor que cero';
    END IF;

    START TRANSACTION;

    IF NOT EXISTS (SELECT 1 FROM clientes WHERE id_cliente = p_id_cliente) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El cliente indicado no existe';
    END IF;

    SELECT stock, precio
      INTO v_stock, v_precio
      FROM productos
     WHERE id_producto = p_id_producto
       FOR UPDATE;   -- bloquea la fila para que dos ventas simultaneas
                     -- no lean el mismo stock y lo vendan dos veces

    IF v_stock IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El producto indicado no existe';
    END IF;

    IF v_stock < p_cantidad THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'No hay stock suficiente para ese producto';
    END IF;

    INSERT INTO ventas (id_cliente, estado, total)
    VALUES (p_id_cliente, 'Pendiente de Pago', v_precio * p_cantidad);

    SET p_id_venta = LAST_INSERT_ID();

    -- Al insertar el detalle, el trigger trg_update_stock_after_insert_venta
    -- descuenta el inventario. Aqui NO se vuelve a descontar.
    INSERT INTO detalle_ventas (id_venta, id_producto, cantidad, precio_unitario_congelado)
    VALUES (p_id_venta, p_id_producto, p_cantidad, v_precio);

    COMMIT;
END$$


-- =====================================================================
-- 2. sp_AgregarNuevoProducto
--    Inserta un producto nuevo y devuelve el id asignado.
--    Valida que el SKU no este repetido para dar un mensaje claro en
--    lugar del error tecnico de clave duplicada.
-- =====================================================================
DROP PROCEDURE IF EXISTS sp_AgregarNuevoProducto$$
CREATE PROCEDURE sp_AgregarNuevoProducto(
    IN  p_nombre       VARCHAR(150),
    IN  p_descripcion  TEXT,
    IN  p_precio       DECIMAL(12,2),
    IN  p_costo        DECIMAL(12,2),
    IN  p_stock        INT,
    IN  p_sku          VARCHAR(40),
    IN  p_id_categoria INT,
    IN  p_id_proveedor INT,
    OUT p_id_producto  INT
)
BEGIN
    IF EXISTS (SELECT 1 FROM productos WHERE sku = p_sku) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Ya existe un producto con ese SKU';
    END IF;

    IF p_precio <= p_costo THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El precio de venta debe ser mayor que el costo';
    END IF;

    INSERT INTO productos
        (nombre, descripcion, precio, costo, stock, sku, id_categoria, id_proveedor)
    VALUES
        (p_nombre, p_descripcion, p_precio, p_costo, p_stock, p_sku, p_id_categoria, p_id_proveedor);

    SET p_id_producto = LAST_INSERT_ID();
END$$


-- =====================================================================
-- 3. sp_ActualizarDireccionCliente
--    Actualiza la direccion de envio de un cliente.
-- =====================================================================
DROP PROCEDURE IF EXISTS sp_ActualizarDireccionCliente$$
CREATE PROCEDURE sp_ActualizarDireccionCliente(
    IN p_id_cliente      INT,
    IN p_nueva_direccion VARCHAR(255)
)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM clientes WHERE id_cliente = p_id_cliente) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El cliente indicado no existe';
    END IF;

    UPDATE clientes
       SET direccion_envio = p_nueva_direccion
     WHERE id_cliente = p_id_cliente;

    SELECT id_cliente, direccion_envio FROM clientes WHERE id_cliente = p_id_cliente;
END$$


-- =====================================================================
-- 4. sp_ProcesarDevolucion
--    Gestiona la devolucion de un producto: repone el inventario y
--    calcula el credito a favor del cliente.
--    El credito se calcula con precio_unitario_congelado, no con el
--    precio actual: se le devuelve lo que pago, no lo que cuesta hoy.
-- =====================================================================
DROP PROCEDURE IF EXISTS sp_ProcesarDevolucion$$
CREATE PROCEDURE sp_ProcesarDevolucion(
    IN  p_id_venta       INT,
    IN  p_id_producto    INT,
    IN  p_cantidad       INT,
    IN  p_motivo         VARCHAR(255),
    OUT p_monto_credito  DECIMAL(12,2)
)
BEGIN
    DECLARE v_precio_pagado    DECIMAL(12,2);
    DECLARE v_cantidad_comprada INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_monto_credito = NULL;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT precio_unitario_congelado, cantidad
      INTO v_precio_pagado, v_cantidad_comprada
      FROM detalle_ventas
     WHERE id_venta = p_id_venta
       AND id_producto = p_id_producto;

    IF v_cantidad_comprada IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Ese producto no aparece en el detalle de esa venta';
    END IF;

    IF p_cantidad <= 0 OR p_cantidad > v_cantidad_comprada THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La cantidad a devolver no es valida para esa venta';
    END IF;

    UPDATE productos
       SET stock = stock + p_cantidad
     WHERE id_producto = p_id_producto;

    SET p_monto_credito = v_precio_pagado * p_cantidad;

    COMMIT;

    SELECT p_id_venta        AS venta,
           p_id_producto     AS producto,
           p_cantidad        AS unidades_devueltas,
           p_motivo          AS motivo,
           p_monto_credito   AS credito_generado;
END$$


-- =====================================================================
-- 5. sp_ObtenerHistorialComprasCliente
--    Historial completo de compras de un cliente, linea por linea.
-- =====================================================================
DROP PROCEDURE IF EXISTS sp_ObtenerHistorialComprasCliente$$
CREATE PROCEDURE sp_ObtenerHistorialComprasCliente(
    IN p_id_cliente INT
)
BEGIN
    SELECT v.id_venta,
           v.fecha_venta,
           v.estado,
           p.nombre                                        AS producto,
           d.cantidad,
           d.precio_unitario_congelado,
           (d.cantidad * d.precio_unitario_congelado)      AS subtotal,
           v.total                                         AS total_de_la_venta
      FROM ventas v
      JOIN detalle_ventas d ON d.id_venta    = v.id_venta
      JOIN productos      p ON p.id_producto = d.id_producto
     WHERE v.id_cliente = p_id_cliente
     ORDER BY v.fecha_venta DESC, p.nombre;
END$$


-- =====================================================================
-- 6. sp_AjustarNivelStock
--    Ajuste manual de inventario, por ejemplo tras un conteo fisico.
--    Devuelve el valor anterior y el nuevo junto con el motivo, para
--    que el ajuste quede documentado.
-- =====================================================================
DROP PROCEDURE IF EXISTS sp_AjustarNivelStock$$
CREATE PROCEDURE sp_AjustarNivelStock(
    IN p_id_producto INT,
    IN p_nuevo_stock INT,
    IN p_motivo      VARCHAR(255)
)
BEGIN
    DECLARE v_stock_anterior INT;

    IF p_nuevo_stock < 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El stock no puede quedar en un valor negativo';
    END IF;

    SELECT stock INTO v_stock_anterior FROM productos WHERE id_producto = p_id_producto;

    IF v_stock_anterior IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El producto indicado no existe';
    END IF;

    UPDATE productos SET stock = p_nuevo_stock WHERE id_producto = p_id_producto;

    SELECT p_id_producto    AS producto,
           v_stock_anterior AS stock_anterior,
           p_nuevo_stock    AS stock_nuevo,
           (p_nuevo_stock - v_stock_anterior) AS diferencia,
           p_motivo         AS motivo;
END$$


-- =====================================================================
-- 7. sp_EliminarClienteDeFormaSegura
--    Anonimiza al cliente en lugar de borrarlo.
--
--    Un DELETE romperia la integridad referencial con ventas y dejaria
--    las compras historicas huerfanas. Anonimizar conserva el historico
--    de ventas y elimina los datos personales identificables.
-- =====================================================================
DROP PROCEDURE IF EXISTS sp_EliminarClienteDeFormaSegura$$
CREATE PROCEDURE sp_EliminarClienteDeFormaSegura(
    IN p_id_cliente INT
)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM clientes WHERE id_cliente = p_id_cliente) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El cliente indicado no existe';
    END IF;

    UPDATE clientes
       SET nombre           = 'Usuario',
           apellido         = 'Anonimizado',
           email            = CONCAT('eliminado_', p_id_cliente, '@anonimo.local'),
           contrasena       = 'CUENTA_ELIMINADA',
           direccion_envio  = NULL,
           fecha_nacimiento = NULL,
           activo           = FALSE
     WHERE id_cliente = p_id_cliente;

    SELECT id_cliente, nombre, apellido, email, activo
      FROM clientes WHERE id_cliente = p_id_cliente;
END$$


-- =====================================================================
-- 8. sp_AplicarDescuentoPorCategoria
--    Aplica un descuento a todos los productos activos de una
--    categoria, reutilizando fn_AplicarDescuento del archivo 03.
--    Cada UPDATE deja su rastro en log_cambios_precio via el trigger 1.
-- =====================================================================
DROP PROCEDURE IF EXISTS sp_AplicarDescuentoPorCategoria$$
CREATE PROCEDURE sp_AplicarDescuentoPorCategoria(
    IN p_id_categoria INT,
    IN p_porcentaje   DECIMAL(5,2)
)
BEGIN
    DECLARE v_afectados INT DEFAULT 0;

    IF p_porcentaje <= 0 OR p_porcentaje >= 100 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El porcentaje de descuento debe estar entre 0 y 100';
    END IF;

    UPDATE productos
       SET precio = fn_AplicarDescuento(precio, p_porcentaje)
     WHERE id_categoria = p_id_categoria
       AND activo = TRUE;

    SET v_afectados = ROW_COUNT();

    SELECT p_id_categoria AS categoria,
           p_porcentaje   AS descuento_aplicado,
           v_afectados    AS productos_actualizados;
END$$


-- =====================================================================
-- 9. sp_GenerarReporteMensualVentas
--    Reporte consolidado de ventas para un mes y anio dados.
--    Devuelve el resumen del mes y el desglose por categoria.
-- =====================================================================
DROP PROCEDURE IF EXISTS sp_GenerarReporteMensualVentas$$
CREATE PROCEDURE sp_GenerarReporteMensualVentas(
    IN p_mes  INT,
    IN p_anio INT
)
BEGIN
    IF p_mes < 1 OR p_mes > 12 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El mes debe estar entre 1 y 12';
    END IF;

    -- Resumen del mes
    SELECT
        p_anio                                                          AS anio,
        p_mes                                                           AS mes,
        COUNT(*)                                                        AS total_ventas,
        SUM(CASE WHEN estado <> 'Cancelado' THEN total ELSE 0 END)      AS ingresos_totales,
        ROUND(AVG(CASE WHEN estado <> 'Cancelado' THEN total END), 2)   AS ticket_promedio,
        SUM(estado = 'Cancelado')                                       AS ventas_canceladas
      FROM ventas
     WHERE MONTH(fecha_venta) = p_mes
       AND YEAR(fecha_venta)  = p_anio;

    -- Desglose por categoria
    SELECT c.nombre                                          AS categoria,
           SUM(d.cantidad)                                   AS unidades,
           SUM(d.cantidad * d.precio_unitario_congelado)     AS ingresos
      FROM ventas v
      JOIN detalle_ventas d ON d.id_venta    = v.id_venta
      JOIN productos      p ON p.id_producto = d.id_producto
      LEFT JOIN categorias c ON c.id_categoria = p.id_categoria
     WHERE MONTH(v.fecha_venta) = p_mes
       AND YEAR(v.fecha_venta)  = p_anio
       AND v.estado <> 'Cancelado'
     GROUP BY c.nombre
     ORDER BY ingresos DESC;
END$$


-- =====================================================================
-- 10. sp_CambiarEstadoPedido
--     Cambia el estado de un pedido validando que el valor recibido
--     pertenezca a la lista permitida por el ENUM. Sin esta validacion,
--     un valor invalido se guardaria como cadena vacia en lugar de
--     provocar un error visible.
-- =====================================================================
DROP PROCEDURE IF EXISTS sp_CambiarEstadoPedido$$
CREATE PROCEDURE sp_CambiarEstadoPedido(
    IN p_id_venta     INT,
    IN p_nuevo_estado VARCHAR(20)
)
BEGIN
    DECLARE v_estado_actual VARCHAR(20);

    IF p_nuevo_estado NOT IN
       ('Pendiente de Pago','Procesando','Enviado','Entregado','Cancelado') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Estado no valido para un pedido';
    END IF;

    SELECT estado INTO v_estado_actual FROM ventas WHERE id_venta = p_id_venta;

    IF v_estado_actual IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La venta indicada no existe';
    END IF;

    UPDATE ventas SET estado = p_nuevo_estado WHERE id_venta = p_id_venta;

    SELECT p_id_venta      AS venta,
           v_estado_actual AS estado_anterior,
           p_nuevo_estado  AS estado_nuevo;
END$$

DELIMITER ;


-- =====================================================================
-- PRUEBAS DE LOS 10 PROCEDIMIENTOS
-- =====================================================================

SELECT ROUTINE_NAME AS procedimiento, ROUTINE_TYPE AS tipo
FROM information_schema.ROUTINES
WHERE ROUTINE_SCHEMA = 'ecommerce_db' AND ROUTINE_TYPE = 'PROCEDURE'
ORDER BY ROUTINE_NAME;

-- --- 1. Nueva venta: el cliente 3 compra 2 mouse --------------------
SELECT stock AS stock_producto_2_antes FROM productos WHERE id_producto = 2;
CALL sp_RealizarNuevaVenta(3, 2, 2, @id_venta_nueva);
SELECT @id_venta_nueva AS id_venta_creada;
SELECT * FROM ventas WHERE id_venta = @id_venta_nueva;
SELECT * FROM detalle_ventas WHERE id_venta = @id_venta_nueva;
-- El stock debe haber bajado exactamente 2 unidades, no 4
SELECT stock AS stock_producto_2_despues FROM productos WHERE id_producto = 2;

-- --- 2. Nuevo producto ----------------------------------------------
CALL sp_AgregarNuevoProducto('Gorra Deportiva', 'Gorra ajustable con visera',
                             45000, 20000, 40, 'DEP-GOR-012', 4, 5, @id_prod_nuevo);
SELECT @id_prod_nuevo AS id_producto_creado;
SELECT id_producto, nombre, precio, sku FROM productos WHERE id_producto = @id_prod_nuevo;

-- --- 3. Actualizar direccion ----------------------------------------
CALL sp_ActualizarDireccionCliente(5, 'Cra 15 #10-20, Bucaramanga');

-- --- 4. Procesar devolucion (venta 4 incluye el producto 8) ----------
SELECT stock AS stock_producto_8_antes FROM productos WHERE id_producto = 8;
CALL sp_ProcesarDevolucion(4, 8, 1, 'El producto llego danado', @credito);
SELECT @credito AS credito_generado;
SELECT stock AS stock_producto_8_despues FROM productos WHERE id_producto = 8;

-- --- 5. Historial de compras del cliente 1 --------------------------
CALL sp_ObtenerHistorialComprasCliente(1);

-- --- 6. Ajuste manual de stock --------------------------------------
CALL sp_AjustarNivelStock(11, 60, 'Conteo fisico de bodega');

-- --- 7. Anonimizar un cliente ---------------------------------------
CALL sp_EliminarClienteDeFormaSegura(7);
-- Sus ventas siguen existiendo: la integridad referencial se mantiene
SELECT id_venta, id_cliente, total FROM ventas WHERE id_cliente = 7;

-- --- 8. Descuento del 10% a la categoria Ropa -----------------------
SELECT id_producto, nombre, precio AS precio_antes FROM productos WHERE id_categoria = 2;
CALL sp_AplicarDescuentoPorCategoria(2, 10);
SELECT id_producto, nombre, precio AS precio_despues FROM productos WHERE id_categoria = 2;
-- El trigger de auditoria registro cada cambio de precio
SELECT nombre_producto, precio_anterior, precio_nuevo, porcentaje_cambio
FROM log_cambios_precio ORDER BY id_auditoria DESC LIMIT 2;

-- --- 9. Reporte mensual (noviembre de 2025) -------------------------
CALL sp_GenerarReporteMensualVentas(11, 2025);

-- --- 10. Cambio de estado de un pedido ------------------------------
CALL sp_CambiarEstadoPedido(9, 'Enviado');
SELECT id_venta, estado FROM ventas WHERE id_venta = 9;

-- --- Pruebas de validacion: deben ser rechazadas --------------------
-- (sp_probar_error se define en 05_Triggers.sql)
CALL sp_probar_error('CALL sp_CambiarEstadoPedido(9, ''Despachado'')',
                     'sp_CambiarEstadoPedido: rechazar un estado invalido');
CALL sp_probar_error('CALL sp_RealizarNuevaVenta(3, 4, 9999, @x)',
                     'sp_RealizarNuevaVenta: rechazar una venta sin stock');
CALL sp_probar_error('CALL sp_ProcesarDevolucion(4, 1, 1, ''prueba'', @y)',
                     'sp_ProcesarDevolucion: rechazar un producto ajeno a la venta');
