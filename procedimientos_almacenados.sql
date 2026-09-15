

USE ecommerce_db;


-- ====================================
-- 1. sp_RealizarNuevaVenta 
-- registra una venta de un solo producto: revisa el stock, crea la
-- venta, inserta la linea de detalle y descuenta el stock
-- ====================================
DELIMITER $$

DROP PROCEDURE IF EXISTS sp_RealizarNuevaVenta$$

CREATE PROCEDURE sp_RealizarNuevaVenta(
    IN p_id_cliente INT,
    IN p_id_producto INT,
    IN p_cantidad INT,
    OUT p_id_venta INT
)
BEGIN
    DECLARE v_stock_disponible INT;
    DECLARE v_precio_actual DECIMAL(12,2);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT stock, precio
    INTO v_stock_disponible, v_precio_actual
    FROM productos
    WHERE id_producto = p_id_producto;

    IF v_stock_disponible < p_cantidad THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'No hay stock suficiente para ese producto';
    END IF;

    INSERT INTO ventas (id_cliente, estado, total)
    VALUES (p_id_cliente, 'Pendiente de Pago', v_precio_actual * p_cantidad);

    SET p_id_venta = LAST_INSERT_ID();

    INSERT INTO detalle_ventas (id_venta, id_producto, cantidad, precio_unitario_congelado)
    VALUES (p_id_venta, p_id_producto, p_cantidad, v_precio_actual);

    UPDATE productos
    SET stock = stock - p_cantidad
    WHERE id_producto = p_id_producto;

    COMMIT;
END$$

DELIMITER ;

-- ====================================
-- 2. sp_AgregarNuevoProducto
-- inserta un producto nuevo y devuelve el id que le quedo asignado
-- ====================================
DELIMITER $$

DROP PROCEDURE IF EXISTS sp_AgregarNuevoProducto$$

CREATE PROCEDURE sp_AgregarNuevoProducto(
    IN p_nombre VARCHAR(150),
    IN p_descripcion TEXT,
    IN p_precio DECIMAL(12,2),
    IN p_costo DECIMAL(12,2),
    IN p_stock INT,
    IN p_sku VARCHAR(40),
    IN p_id_categoria INT,
    IN p_id_proveedor INT,
    OUT p_id_producto INT
)
BEGIN
    INSERT INTO productos (nombre, descripcion, precio, costo, stock, sku, id_categoria, id_proveedor)
    VALUES (p_nombre, p_descripcion, p_precio, p_costo, p_stock, p_sku, p_id_categoria, p_id_proveedor);

    SET p_id_producto = LAST_INSERT_ID();
END$$

DELIMITER ;


-- ====================================
-- 3. sp_ActualizarDireccionCliente
-- actualiza la direccion de envio de un cliente
-- ====================================
DELIMITER $$

DROP PROCEDURE IF EXISTS sp_ActualizarDireccionCliente$$

CREATE PROCEDURE sp_ActualizarDireccionCliente(
    IN p_id_cliente INT,
    IN p_nueva_direccion VARCHAR(255)
)
BEGIN
    UPDATE clientes
    SET direccion_envio = p_nueva_direccion
    WHERE id_cliente = p_id_cliente;
END$$

DELIMITER ;


-- ====================================
-- 4. sp_ProcesarDevolucion
-- devuelve productos de una venta ya hecha: repone el stock y calcula
-- el credito a favor del cliente (cantidad x precio que pago en su momento)
-- ====================================
DELIMITER $$

DROP PROCEDURE IF EXISTS sp_ProcesarDevolucion$$

CREATE PROCEDURE sp_ProcesarDevolucion(
    IN p_id_venta INT,
    IN p_id_producto INT,
    IN p_cantidad INT,
    IN p_motivo VARCHAR(255),
    OUT p_monto_credito DECIMAL(12,2)
)
BEGIN
    DECLARE v_precio_pagado DECIMAL(12,2);
    DECLARE v_cantidad_comprada INT;

    SELECT precio_unitario_congelado, cantidad
    INTO v_precio_pagado, v_cantidad_comprada
    FROM detalle_ventas
    WHERE id_venta = p_id_venta AND id_producto = p_id_producto;

    IF v_cantidad_comprada IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Ese producto no esta en el detalle de esa venta';
    END IF;

    IF p_cantidad > v_cantidad_comprada THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'No se puede devolver mas cantidad de la que se compro';
    END IF;

    UPDATE productos
    SET stock = stock + p_cantidad
    WHERE id_producto = p_id_producto;

    SET p_monto_credito = v_precio_pagado * p_cantidad;

b      SELECT p_motivo AS motivo_recibido, p_monto_credito AS credito_generado;
END$$

DELIMITER ;


-- ====================================
-- 5. sp_ObtenerHistorialComprasCliente
-- devuelve todo el historial de compras de un cliente, con el detalle
-- de que productos compro en cada venta
-- ====================================
DELIMITER $$

DROP PROCEDURE IF EXISTS sp_ObtenerHistorialComprasCliente$$

CREATE PROCEDURE sp_ObtenerHistorialComprasCliente(
    IN p_id_cliente INT
)
BEGIN
    SELECT v.id_venta,
           v.fecha_venta,
           v.estado,
           p.nombre AS producto,
           d.cantidad,
           d.precio_unitario_congelado,
           (d.cantidad * d.precio_unitario_congelado) AS subtotal
    FROM ventas v
    JOIN detalle_ventas d ON d.id_venta = v.id_venta
    JOIN productos p ON p.id_producto = d.id_producto
    WHERE v.id_cliente = p_id_cliente
    ORDER BY v.fecha_venta DESC;
END$$

DELIMITER ;


-- ====================================
-- 6. sp_AjustarNivelStock
-- permite ajustar el stock de un producto a mano, dejando el motivo
-- del ajuste como referencia (no se guarda en tabla, solo se devuelve)
-- ====================================
DELIMITER $$

DROP PROCEDURE IF EXISTS sp_AjustarNivelStock$$

CREATE PROCEDURE sp_AjustarNivelStock(
    IN p_id_producto INT,
    IN p_nuevo_stock INT,
    IN p_motivo VARCHAR(255)
)
BEGIN
    IF p_nuevo_stock < 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El stock no puede quedar en un numero negativo';
    END IF;

    UPDATE productos
    SET stock = p_nuevo_stock
    WHERE id_producto = p_id_producto;

    SELECT p_id_producto AS producto_ajustado, p_nuevo_stock AS nuevo_stock, p_motivo AS motivo;
END$$

DELIMITER ;


-- ====================================
-- 7. sp_EliminarClienteDeFormaSegura
-- en vez de borrar al cliente (eso rompería las ventas ya hechas),
-- le cambia los datos personales por unos genericos. asi se mantiene
-- la integridad referencial pero ya no queda informacion identificable.
-- ====================================
DELIMITER $$

DROP PROCEDURE IF EXISTS sp_EliminarClienteDeFormaSegura$$

CREATE PROCEDURE sp_EliminarClienteDeFormaSegura(
    IN p_id_cliente INT
)
BEGIN
    UPDATE clientes
    SET nombre = 'Usuario',
        apellido = 'Eliminado',
        email = CONCAT('eliminado_', p_id_cliente, '@anonimo.local'),
        contrasena = 'CUENTA_ELIMINADA',
        direccion_envio = NULL
    WHERE id_cliente = p_id_cliente;
END$$

DELIMITER ;


-- ====================================
-- 8. sp_AplicarDescuentoPorCategoria
-- baja el precio de todos los productos de una categoria, usando
-- la funcion fn_AplicarDescuento que ya hicimos en el archivo 03
-- ====================================
DELIMITER $$

DROP PROCEDURE IF EXISTS sp_AplicarDescuentoPorCategoria$$

CREATE PROCEDURE sp_AplicarDescuentoPorCategoria(
    IN p_id_categoria INT,
    IN p_porcentaje DECIMAL(5,2)
)
BEGIN
    UPDATE productos
    SET precio = fn_AplicarDescuento(precio, p_porcentaje)
    WHERE id_categoria = p_id_categoria;
END$$

DELIMITER ;


-- ====================================
-- 9. sp_GenerarReporteMensualVentas
-- genera un resumen de ventas para un mes y un anio especifico
-- ====================================
DELIMITER $$

DROP PROCEDURE IF EXISTS sp_GenerarReporteMensualVentas$$

CREATE PROCEDURE sp_GenerarReporteMensualVentas(
    IN p_mes INT,
    IN p_anio INT
)
BEGIN
    SELECT
        COUNT(*) AS total_ventas,
        SUM(total) AS ingresos_totales,
        ROUND(AVG(total), 2) AS ticket_promedio,
        SUM(CASE WHEN estado = 'Cancelado' THEN 1 ELSE 0 END) AS ventas_canceladas
    FROM ventas
    WHERE MONTH(fecha_venta) = p_mes
    AND YEAR(fecha_venta) = p_anio;
END$$

DELIMITER ;


-- ====================================
-- 10. sp_CambiarEstadoPedido
-- cambia el estado de una venta (por ejemplo de Procesando a Enviado)
-- ====================================
DELIMITER $$

DROP PROCEDURE IF EXISTS sp_CambiarEstadoPedido$$

CREATE PROCEDURE sp_CambiarEstadoPedido(
    IN p_id_venta INT,
    IN p_nuevo_estado VARCHAR(20)
)
BEGIN
    UPDATE ventas
    SET estado = p_nuevo_estado
    WHERE id_venta = p_id_venta;

    SELECT p_id_venta AS venta, p_nuevo_estado AS nuevo_estado;
END$$

DELIMITER ;


-- ====================================
-- pruebas rapidas
-- ====================================

-- 1. nueva venta: cliente 3 compra 1 mouse y 2 balones
CALL sp_RealizarNuevaVenta(3, '[{"id_producto":2,"cantidad":1},{"id_producto":9,"cantidad":2}]', @id_venta_nueva);
SELECT @id_venta_nueva AS id_venta_creada;
SELECT * FROM ventas WHERE id_venta = @id_venta_nueva;
SELECT * FROM detalle_ventas WHERE id_venta = @id_venta_nueva;

-- 2. nuevo producto
CALL sp_AgregarNuevoProducto('Gorra Deportiva', 'Gorra ajustable con visera', 45000, 20000, 40, 'DEP-GOR-012', 4, 5, @id_prod_nuevo);
SELECT @id_prod_nuevo AS id_producto_creado;

-- 3. actualizar direccion
CALL sp_ActualizarDireccionCliente(5, 'Nueva direccion de prueba #10-20');
SELECT direccion_envio FROM clientes WHERE id_cliente = 5;

-- 4. procesar devolucion (usamos la venta 4, que tiene el producto 8)
CALL sp_ProcesarDevolucion(4, 8, 1, 'Producto llego danado', @credito);
SELECT @credito AS credito_generado;

-- 5. historial de compras del cliente 1
CALL sp_ObtenerHistorialComprasCliente(1);

-- 6. ajustar stock
CALL sp_AjustarNivelStock(11, 60, 'Reabastecimiento programado');

-- 7. eliminar cliente de forma segura (usamos el cliente 7 de prueba)
CALL sp_EliminarClienteDeFormaSegura(7);
SELECT nombre, apellido, email FROM clientes WHERE id_cliente = 7;

-- 8. descuento por categoria (10% a toda la categoria 2, Ropa)
CALL sp_AplicarDescuentoPorCategoria(2, 10);
SELECT nombre, precio FROM productos WHERE id_categoria = 2;

-- 9. reporte mensual (noviembre 2025, deberia mostrar 2 ventas)
CALL sp_GenerarReporteMensualVentas(11, 2025);

-- 10. cambiar estado de pedido
CALL sp_CambiarEstadoPedido(9, 'Enviado');
SELECT id_venta, estado FROM ventas WHERE id_venta = 9;