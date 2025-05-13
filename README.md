# BD_Proyecto3
Diseño y desarrollo  de un Sistema de Control de Pedidos para una Cafetería básica

Contenido del GitHub:
ARCHIVO Cafeteria.py
ARCHIVO BD_Cafeteria.sql
DOCUMENTO BD_Proyecto3.docx



BASE DE DATOS.
Para poder tener la base de datos en su máquina siga los siguientes pasos:
Abra el archivo "BD_Cafeteria.sql" en pgAdmin 4.
Si esto no es posible copie y pegue todo el texto y cópielo en una base de datos llamada "Cafeteria".
Seleccione las 12 tablas y ejecute el script.
Seleccione las 4 funciones y junto a sus triggers y ejecute el script.
Para finalizar seleccione el DO y ejecute el generador de datos.



INTERFAZ DE REPORTES.
Abre el archivo Cafeteria.py
Para preparar el entorno de Pyton debe instalar lo siguiente:
pip install psycopg2-binary
pip install streamlit
pip install pandas
pip install matplotlib
pip install reportlab

Como se ve en las primeras líneas del archivo Cafeteria.py, se debe conectar a la base de datos, por lo que es necesario que el pgAdmin4 esté abierto con la base de datos BD_Cafeteria.sql anteriormente mencionada.

Para ejecutar el programa debe colocar lo siguiente en la terminal:
streamlit run Cafeteria.py



EN EL LOCALHOST.
Encontrará los distintos reportes junto con filtros en los cuales podrá cambiar la fecha del pedido, el monto máximo del pedido, el estado del pedido y la categoría.
Algunos reportes tendrán una gráfica que representará a los pedidos dentro de las condiciones que el filtro nos mostrará.

Tenemos la opción en cada reporte de descargar las tablas en un archivo CSV o en un archivo PDF.
Como recomendación es mejor colocar la fecha de fin la fecha del siguiente día al actual, para que pueda ver todos los datos que recién se agregaron a la base de datos.



ESTRUCTURA PRINCIPAL DEL SQL.
1. CREACIÓN DE TABLAS  (12 tablas)
   ├─ clientes, telefono_clientes
   ├─ empleados
   ├─ categorias, productos
   ├─ proveedores, telefonos_proveedores, productos_proveedores
   ├─ mesas_cafe
   ├─ pedidos, items_orden, pagos
2. FUNCIONES Y TRIGGERS
   ├─ trg_items_orden_set_prices      (before insert/update)
   ├─ trg_pedidos_update_total        (after insert/update/delete)
   ├─ trg_pagos_check_monto           (before insert)
   └─ trg_bloquear_pago_cancelado     (before insert/update)
3. GENERADOR DE DATOS (bloque DO)



NOTAS.
Los pedidos cancelados no admiten pagos: el trigger trg_bloquear_pago_cancelado lanza excepción.

El trigger trg_pagos_check_monto evita sobre-pagos y omite validación cuando el pedido está cancelado.

El generador asigna fechas de los últimos 14 días, estados y métodos de pago al azar → prueba realista para los filtros.



CRÉDITOS.
Grupo 6 – Abner Gabriel Mejicanos, Alejandro Rivera, María José Yee
Universidad del Valle de Guatemala — CC3088 Base de Datos — Ciclo 1-2025
