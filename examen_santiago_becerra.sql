-- EXAMEN DEL GOAT SANTIAGO BECERRA VASQUEZ

USE ecommerce_db;


-- Activamos el event_scheduler
SET GLOBAL event_scheduler = ON;

-- Hacemos el alter table en clientes

ALTER TABLE clientes ADD COLUMN fecha_ultima_compra DATETIME NULL;

-- Hacer trigger de mantener actualizado la fecha ultima compra

DELIMITER $$

DROP TRIGGER IF EXISTS trg_actualizar_fecha_ultima_compra;
CREATE TRIGGER trg_actualizar_fecha_ultima_compra
AFTER INSERT ON ventas
FOR EACH ROW
BEGIN
	UPDATE clientes
	SET fecha_ultima_compra = NOW()
	Where id_cliente = NEW.id_cliente;
END;

DELIMITER ;

-- PRUEBA TRIGGER

INSERT INTO ventas (id_venta, id_cliente, fecha_venta, estado) VALUES
( 11, 2, '2026-09-22 10:23:00', 'Entregado');

-- Creamos el campo de activo
ALTER TABLE clientes ADD COLUMN activo VARCHAR(50) NOT NUll; 

-- Creamos el evento 

DELIMITER $$

DROP EVENT IF EXISTS evt_desactivar_cuentas_inactivas$$
CREATE EVENT evt_desactivar_cuentas_inactivas
ON SCHEDULE EVERY 1 MONTH
	STARTS DATE_FORMAT(NOW() + INTERVAL 1 MONTH, '%Y-%m-01 00:00:00')
DO
BEGIN
	UPDATE clientes
	SET activo = 'FALSE'
	WHERE activo = 'TRUE'
		AND(
		fecha_ultima_compra < NOW() - INTERVAL 2 YEAR 
		OR (fecha_ultima_compra IS NULL AND fecha_registro < NOW() - INTERVAL 2 YEAR)
		); 
END;

DELIMITER ; 

-- Di todo de mi profe porfa