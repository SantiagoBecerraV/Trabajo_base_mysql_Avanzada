
-- trigger

DELIMITER $$

CREATE TRIGGER trg_actualizar_fecha_ultima_compra $$
AFTER INSERT ON ventas
FOR EACH ROW
BEGIN
	UPDATE clientes 
	SET fecha_ultima_compra = NOW()
	Where id_cliente = NEW.id_cliente
END $$

DELIMITER ;

-- evento 
event_scheduler = ON;

CREATE EVENT evt_desactivar_cuentas_inactivas
ON SCHEDULE EVERY 1 MONTH
    STARTS '2026-22-09 00:00:00'
ON COMPLETION PRESERVE
ENABLE
COMMENT 'Desactiva cuentas de clientes sin actividad en mas de dos años'
DO
BEGIN
    UPDATE clientes
       SET activo = FALSE
     WHERE activo = TRUE
       AND IFNULL(fecha_ultimo_pedido, fecha_registro) < NOW() - INTERVAL 2 YEAR;

    INSERT INTO log_ejecucion_eventos (nombre_evento, filas_afectadas)
    VALUES ('evt_desactivar_cuentas_inactivas', ROW_COUNT());
END$$

-- alter table --

ALTER TABLE clientes ADD COLUMN IF NOT EXISTS fecha_ultima_compra DATETIME NULL;


