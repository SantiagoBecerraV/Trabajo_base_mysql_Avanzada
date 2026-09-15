# Proyecto de Base de Datos para un E-commerce

Núcleo de base de datos para una tienda en línea, construido sobre **MySQL 8.0**.
El esquema gestiona el catálogo de productos, el inventario, los clientes y el
ciclo de vida completo de las ventas. Sobre esa base se implementa la lógica
avanzada del sistema: consultas analíticas, funciones de negocio reutilizables,
un esquema de seguridad basado en roles, triggers que garantizan la integridad
de los datos, eventos programados de mantenimiento y procedimientos almacenados
transaccionales.

---

## Integrantes

- Santiago Becerra V.
- Cristian Solano

---

## Requisitos

| Requisito | Detalle |
|---|---|
| Motor | MySQL 8.0 o superior |
| Privilegios | Una cuenta con permisos de administración (`root` o equivalente) |
| Cliente | MySQL Workbench, DBeaver o la línea de comandos `mysql` |

---

## Instrucciones de ejecución

Los archivos deben ejecutarse **en orden numérico**. Cada uno depende de los
anteriores; ejecutarlos desordenados produce errores de objetos inexistentes.

```bash
mysql -u root -p < 01_Esquema_y_Datos.sql
mysql -u root -p < 02_Consultas_Avanzadas.sql
mysql -u root -p < 03_Funciones.sql
mysql -u root -p < 04_Seguridad.sql
mysql -u root -p < 05_Triggers.sql
mysql -u root -p < 06_Eventos.sql
mysql -u root -p < 07_Procedimientos_Almacenados.sql
```

Desde MySQL Workbench: abrir cada archivo y ejecutarlo completo
(`Ctrl + Shift + Enter`), respetando el mismo orden.

| Paso | Archivo | Qué hace |
|---|---|---|
| 1 | `01_Esquema_y_Datos.sql` | Crea la base `ecommerce_db`, todas las tablas, los índices y carga los datos de ejemplo. **Borra y recrea la base desde cero.** |
| 2 | `02_Consultas_Avanzadas.sql` | 10 consultas de análisis. Solo lectura: no modifica nada y se puede repetir. |
| 3 | `03_Funciones.sql` | 10 funciones de usuario más sus pruebas. |
| 4 | `04_Seguridad.sql` | 6 roles, 5 usuarios, 2 vistas y la asignación de permisos. |
| 5 | `05_Triggers.sql` | 12 triggers más sus pruebas. |
| 6 | `06_Eventos.sql` | Activa el planificador y crea 10 eventos programados. |
| 7 | `07_Procedimientos_Almacenados.sql` | 10 procedimientos almacenados más sus pruebas. |



## Estructura de la base de datos

### Tablas del negocio

| Tabla | Rol |
|---|---|
| `categorias` | Clasificación de los productos |
| `proveedores` | Quién suministra cada producto |
| `productos` | Catálogo, precios, costos e inventario |
| `clientes` | Usuarios registrados |
| `ventas` | Encabezado de cada transacción |
| `detalle_ventas` | Líneas de la orden (relación N:M entre ventas y productos) |
| `promociones` | Campañas de descuento con vigencia |

### Tablas de auditoría, log y reporte

`log_cambios_precio`, `log_clientes`, `log_ejecucion_eventos`,
`log_ejecucion_eventos_historico`, `reporte_ventas_semanales`,
`niveles_lealtad_clientes`, `lista_reabastecimiento`,
`resumen_ventas_diarias`, `inconsistencias_detectadas`.

### Decisiones de diseño relevantes

**`precio_unitario_congelado`.** La tabla `detalle_ventas` guarda el precio del
momento exacto de la compra en lugar de apuntar a `productos.precio`. Si se
consultara el precio vigente, cualquier cambio de tarifa reescribiría el valor
histórico de todas las ventas pasadas y los reportes de ingresos dejarían de
cuadrar.

**`id_categoria` acepta NULL.** Es deliberado: el trigger
`trg_assign_default_category_on_null` asigna la categoría `General` a los
productos que entran sin clasificar, de modo que ninguno queda huérfano.

**Un solo responsable por cada efecto.** El descuento de inventario ocurre
únicamente en el trigger `trg_update_stock_after_insert_venta`. Los
procedimientos que registran ventas **no** vuelven a descontarlo. Si ambos lo
hicieran, cada venta restaría el stock dos veces.

**Campos derivados.** `clientes.total_gastado`, `clientes.fecha_ultimo_pedido`
y `productos.fecha_modificacion` los mantienen triggers. El archivo `01` los
calcula una sola vez tras la carga masiva, porque esa carga ocurre antes de que
los triggers existan.

---

## Contenido implementado

### `02_Consultas_Avanzadas.sql` — 10 consultas

| # | Consulta | Pregunta de negocio |
|---|---|---|
| 1 | Top 10 productos más vendidos | Qué productos generan más ingresos |
| 2 | Productos con bajas ventas | Qué está en el decil inferior (`NTILE(10)`) |
| 3 | Clientes VIP | Los 5 mayores por valor de vida |
| 4 | Ventas mensuales | Evolución mes a mes |
| 5 | Crecimiento de clientes | Altas por trimestre, con acumulado |
| 6 | Tasa de compra repetida | Qué porcentaje compra más de una vez |
| 7 | Productos comprados juntos | Pares frecuentes para cross-selling |
| 8 | Rotación de inventario | Velocidad de rotación por categoría |
| 9 | Reabastecimiento | Productos bajo su umbral mínimo |
| 10 | Carrito abandonado | Compras iniciadas y no completadas |

### `03_Funciones.sql` — 10 funciones

`fn_CalcularTotalVenta`, `fn_VerificarDisponibilidadStock`,
`fn_ObtenerPrecioProducto`, `fn_CalcularEdadCliente`,
`fn_FormatearNombreCompleto`, `fn_EsClienteNuevo`, `fn_CalcularCostoEnvio`,
`fn_AplicarDescuento`, `fn_ObtenerUltimaFechaCompra`, `fn_ValidarFormatoEmail`.

### `04_Seguridad.sql` — 6 roles y 5 usuarios

| Rol | Alcance |
|---|---|
| `administrador_sistema` | Todos los privilegios sobre `ecommerce_db` |
| `gerente_marketing` | Lectura de ventas, clientes, productos y detalle; ejecuta reportes |
| `analista_datos` | Lectura de las tablas de negocio, **sin acceso a las de auditoría** |
| `empleado_inventario` | `UPDATE` limitado a las columnas `stock` y `ubicacion` |
| `atencion_cliente` | Lectura de clientes y ventas; de productos solo columnas no sensibles |
| `auditor_financiero` | Lectura de ventas, productos y el log de precios |

| Usuario | Rol asignado |
|---|---|
| `admin_user` | `administrador_sistema` |
| `marketing_user` | `gerente_marketing` |
| `inventory_user` | `empleado_inventario` |
| `support_user` | `atencion_cliente` |
| `analyst_user` | `analista_datos` (con límite de consultas por hora) |

También se crean las vistas `v_info_clientes_basica` (enmascara el correo y
oculta contraseña y datos sensibles) y `v_catalogo_publico` (catálogo sin costos
de compra), más la política de caducidad de contraseñas y bloqueo por intentos
fallidos.

> Las contraseñas están en el script para que el proyecto sea reproducible. En
> un entorno real no irían en el repositorio: se cargarían desde variables de
> entorno o desde un gestor de secretos.

### `05_Triggers.sql` — 12 triggers

| # | Trigger | Momento | Qué hace |
|---|---|---|---|
| 1 | `trg_audit_precio_producto_after_update` | AFTER UPDATE | Audita cambios de precio |
| 2 | `trg_check_stock_before_insert_venta` | BEFORE INSERT | Verifica stock antes de vender |
| 3 | `trg_update_stock_after_insert_venta` | AFTER INSERT | Descuenta inventario |
| 4 | `trg_prevent_delete_categoria_with_products` | BEFORE DELETE | Protege categorías con productos |
| 5 | `trg_log_new_customer_after_insert` | AFTER INSERT | Registra cada alta de cliente |
| 6 | `trg_update_total_gastado_cliente` | AFTER INSERT | Acumula el gasto del cliente |
| 7 | `trg_set_fecha_modificacion_producto` | BEFORE UPDATE | Sella la fecha de modificación |
| 8 | `trg_prevent_negative_stock` | BEFORE UPDATE | Bloquea stock negativo |
| 9 | `trg_capitalize_nombre_cliente` | BEFORE INSERT | Normaliza nombre y apellido |
| 10 | `trg_recalculate_total_venta_on_detalle_change` | AFTER UPDATE | Recalcula el total de la venta |
| 12 | `trg_prevent_price_zero_or_less` | BEFORE UPDATE | Bloquea precio cero o negativo |
| 19 | `trg_assign_default_category_on_null` | BEFORE INSERT | Asigna la categoría `General` |

Sobre el trigger 7: va **BEFORE UPDATE** y asigna con `SET NEW.fecha_modificacion`.
Un trigger no puede ejecutar `UPDATE` sobre su propia tabla; MySQL lo rechaza con
el error 1442. `SET NEW` es la forma correcta de modificar la fila en curso.

### `06_Eventos.sql` — 10 eventos programados

| # | Evento | Frecuencia |
|---|---|---|
| 1 | `evt_generate_weekly_sales_report` | Lunes 06:00 |
| 2 | `evt_cleanup_temp_tables_daily` | Diario 03:00 |
| 3 | `evt_archive_old_logs_monthly` | Día 1 del mes, 00:30 |
| 4 | `evt_deactivate_expired_promotions_hourly` | Cada hora |
| 5 | `evt_recalculate_customer_loyalty_tiers_nightly` | Diario 02:00 |
| 6 | `evt_generate_reorder_list_daily` | Diario 05:00 |
| 7 | `evt_rebuild_indexes_weekly` | Lunes 04:00 |
| 8 | `evt_suspend_inactive_accounts_quarterly` | Trimestral |
| 9 | `evt_aggregate_daily_sales_data` | Diario 00:15 |
| 10 | `evt_check_data_consistency_nightly` | Diario 01:00 |

Todos dejan constancia en `log_ejecucion_eventos`, que es la forma de comprobar
que un evento corrió: por definición nadie está mirando cuando se dispara de
madrugada.

**Para probar un evento sin esperar su horario:**

```sql
ALTER EVENT evt_generate_reorder_list_daily
    ON SCHEDULE AT CURRENT_TIMESTAMP + INTERVAL 5 SECOND;

-- esperar unos segundos y revisar
SELECT * FROM log_ejecucion_eventos ORDER BY id_log DESC;
SELECT * FROM lista_reabastecimiento;
```

Al terminar, volver a ejecutar `06_Eventos.sql` para devolver los eventos a su
horario normal.

### `07_Procedimientos_Almacenados.sql` — 10 procedimientos

`sp_RealizarNuevaVenta`, `sp_AgregarNuevoProducto`,
`sp_ActualizarDireccionCliente`, `sp_ProcesarDevolucion`,
`sp_ObtenerHistorialComprasCliente`, `sp_AjustarNivelStock`,
`sp_EliminarClienteDeFormaSegura`, `sp_AplicarDescuentoPorCategoria`,
`sp_GenerarReporteMensualVentas`, `sp_CambiarEstadoPedido`.

`sp_RealizarNuevaVenta` y `sp_ProcesarDevolucion` son transaccionales: usan
`START TRANSACTION` con un `EXIT HANDLER` que hace `ROLLBACK` ante cualquier
error. Sin eso podría quedar un encabezado de venta sin líneas de detalle, que es
exactamente la inconsistencia que busca el evento 10.

`sp_EliminarClienteDeFormaSegura` **anonimiza** en lugar de borrar. Un `DELETE`
rompería la integridad referencial con `ventas` y dejaría huérfanas las compras
históricas.

---

## Verificación

Los archivos `03`, `05`, `06` y `07` terminan con una batería de pruebas que se
ejecuta sola. Varios triggers y procedimientos están diseñados para **provocar un
error** cuando se viola una regla de negocio; si esas pruebas fueran sentencias
sueltas, el cliente de MySQL abortaría el script en la primera.

Para evitarlo, `05_Triggers.sql` define `sp_probar_error`, que ejecuta la
sentencia, captura el error con un `CONTINUE HANDLER` e informa si la regla hizo
su trabajo:

```
+----------------------------------------------------+-----------------------------------------------------------+
| prueba                                             | resultado                                                 |
+----------------------------------------------------+-----------------------------------------------------------+
| Trigger 2: rechazar una venta sin stock suficiente | OK, bloqueado: Stock insuficiente para completar la venta |
+----------------------------------------------------+-----------------------------------------------------------+
```

Así el script corre de principio a fin y además deja evidencia legible de cada
validación.

Para confirmar que todo quedó instalado:

```sql
USE ecommerce_db;

SELECT 'Tablas' AS objeto, COUNT(*) AS cantidad
  FROM information_schema.TABLES
 WHERE TABLE_SCHEMA = 'ecommerce_db' AND TABLE_TYPE = 'BASE TABLE'
UNION ALL SELECT 'Vistas', COUNT(*)
  FROM information_schema.VIEWS  WHERE TABLE_SCHEMA = 'ecommerce_db'
UNION ALL SELECT 'Funciones', COUNT(*)
  FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = 'ecommerce_db' AND ROUTINE_TYPE = 'FUNCTION'
UNION ALL SELECT 'Procedimientos', COUNT(*)
  FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = 'ecommerce_db' AND ROUTINE_TYPE = 'PROCEDURE'
UNION ALL SELECT 'Triggers', COUNT(*)
  FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA = 'ecommerce_db'
UNION ALL SELECT 'Eventos', COUNT(*)
  FROM information_schema.EVENTS  WHERE EVENT_SCHEMA = 'ecommerce_db';
```

Resultado esperado:

| objeto | cantidad |
|---|---|
| Tablas | 16 |
| Vistas | 2 |
| Funciones | 10 |
| Procedimientos | 11 |
| Triggers | 12 |
| Eventos | 10 |

Los procedimientos son 11 porque se incluye `sp_probar_error`, el ayudante de
pruebas. Los triggers son 12: los 10 principales más `trg_prevent_price_zero_or_less`
y `trg_assign_default_category_on_null`.

---

## Solución de problemas

**`ERROR 1419: You do not have the SUPER privilege and binary logging is enabled`**
al crear funciones. Ejecutar como administrador:

```sql
SET GLOBAL log_bin_trust_function_creators = 1;
```

**Los eventos no se ejecutan.** El planificador viene apagado por defecto.
`06_Eventos.sql` lo enciende, pero se puede confirmar con:

```sql
SELECT @@global.event_scheduler;   -- debe devolver ON
SET GLOBAL event_scheduler = ON;
```

**`ERROR 1819` al crear los usuarios.** El componente `validate_password` exige
contraseñas con mayúscula, minúscula, dígito y carácter especial. Las del
archivo `04` ya cumplen ese formato; si la política local es más estricta, hay
que reforzarlas.

**`ERROR 1146: Table doesn't exist` al ejecutar `04_Seguridad.sql`.** Se ejecutó
antes que `01_Esquema_y_Datos.sql`. Los permisos solo se pueden otorgar sobre
tablas que ya existen.
