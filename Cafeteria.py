# ----------------------------------------------------------------------------------------------
# Universidad del Valle de Guatemala
# CC3088 Base de Datos
# (Ciclo 1 ‑ 2025)

# SISTEMA DE CONTROL DE PEDIDOS EN UNA CAFETERÍA

# Grupo 6
# Abner Gabriel Mejicanos
# Alejandro Rivera
# María José Yee


# Requisitos: streamlit, psycopg2-binary, pandas, matplotlib, reportlab, io
# Ejecuta con:  streamlit run Cafeteria.py
# ----------------------------------------------------------------------------------------------
import streamlit as st
import psycopg2
import pandas as pd
import matplotlib.pyplot as plt
from io import BytesIO
from reportlab.lib.pagesizes import letter
from reportlab.pdfgen import canvas
from reportlab.lib.utils import ImageReader


# 1. Conexión ----------------------------------------------------------------------------------
@st.cache_resource
def get_conn():
    return psycopg2.connect(
        host='localhost',
        port=5432,
        dbname='Cafeteria',
        user='postgres',
        password='1234'
    )

conn = get_conn()


cats_df = pd.read_sql(
    "SELECT id_categoria, nombre_categoria FROM categorias ORDER BY 2", conn
)
cat_dict = dict(zip(cats_df.nombre_categoria, cats_df.id_categoria))

# 2. Sidebar – filtros globales ----------------------------------------------------------------
st.sidebar.title("Filtros globales")
fecha_ini = st.sidebar.date_input("Fecha inicio")
fecha_fin = st.sidebar.date_input("Fecha fin")
monto_max = st.sidebar.number_input("Monto máximo", value=100.0, step=10.0)
estado_sel = st.sidebar.selectbox(
    "Estado del pedido",
    ['abierta', 'preparacion', 'lista', 'entregada', 'cancelada']
)

categoria_sel = st.sidebar.selectbox(
    "Categoría",
    ["Todas"] + list(cat_dict.keys())
)

def condicion_categoria(alias: str = "p") -> tuple[str, list]:
    """
    Devuelve (texto_sql, lista_params) según lo elegido
    en el filtro 'categoria_sel'.
    """
    if categoria_sel == "Todas":
        return "", []
    else:
        return f" AND {alias}.id_categoria = %s ", [cat_dict[categoria_sel]]


# 3. Funciones auxiliares ----------------------------------------------------------------------
# CSV GEnerador

def to_csv(df: pd.DataFrame) -> bytes:
    return df.to_csv(index=False).encode("utf-8")

def download_button_csv(df, nombre):
    st.download_button(
        label="📥 Descargar CSV",
        data=to_csv(df),
        file_name=f"{nombre}.csv",
        mime="text/csv"
    )

def tabla_y_descarga(df, nombre):
    st.dataframe(df, hide_index=True)
    download_button_csv(df, nombre)


# PDF Generador
def df_to_pdf_bytes(df: pd.DataFrame, titulo: str) -> bytes:
    buffer = BytesIO()
    c = canvas.Canvas(buffer, pagesize=letter)
    width, height = letter
    y = height - 50
    c.setFont("Helvetica-Bold", 14)
    c.drawString(40, y, titulo)
    y -= 30
    c.setFont("Helvetica", 10)

    # Encabezados________________________________
    for col, x in zip(df.columns, range(40, int(width)-40, 100)):
        c.drawString(x, y, str(col)[:12])
    y -= 15
    # Filas (con un max de 40 en cada pagina)____
    for idx, row in df.iterrows():
        if y < 50:
            c.showPage(); y = height - 50
        for val, x in zip(row, range(40, int(width)-40, 100)):
            c.drawString(x, y, str(val)[:12])
        y -= 12
    c.save()
    buffer.seek(0)
    return buffer.getvalue()

def df_to_pdf_bytes(df: pd.DataFrame, titulo: str, fig: plt.Figure | None = None) -> bytes:
    buffer = BytesIO()
    c = canvas.Canvas(buffer, pagesize=letter)
    width, height = letter

    # Título _________________________
    y = height - 40
    c.setFont("Helvetica-Bold", 14)
    c.drawString(40, y, titulo)
    y -= 25
    c.setFont("Helvetica", 10)

    # Gráfica __________
    if fig is not None:
        img_buf = BytesIO()
        fig.savefig(img_buf, format="png", bbox_inches="tight")
        img_buf.seek(0)
        img = ImageReader(img_buf)
        img_width, img_height = img.getSize()
        ratio = min((width - 80) / img_width, 300 / img_height)  # máx 300 px de alto
        img_width  *= ratio
        img_height *= ratio
        c.drawImage(img, 40, y - img_height, width=img_width, height=img_height)
        y -= img_height + 20

    # Encabezados ________________
    for col, x in zip(df.columns, range(40, int(width)-40, 100)):
        c.drawString(x, y, str(col)[:12])
    y -= 15

    # Filas _________________
    for _, row in df.iterrows():
        if y < 50:
            c.showPage(); y = height - 40
            c.setFont("Helvetica", 10)
        for val, x in zip(row, range(40, int(width)-40, 100)):
            c.drawString(x, y, str(val)[:12])
        y -= 12

    c.save()
    buffer.seek(0)
    return buffer.getvalue()

# 4. Tabs de reportes --------------------------------------------------------------------------
tab1, tab2, tab3, tab4, tab5 = st.tabs(
    ["Pedidos (detalle)",
     "Ventas por día",
     "Ingresos por método",
     "Productos más vendidos",
     "Pedidos abiertos"]
)


# REPORTE 1 – Pedidos detalle ------------------------------------------------------------------
with tab1:
    st.header("Pedidos filtrados")
    sql = """
        SELECT id_pedido, fecha_hora_pedido,
               total, estado_pedido
        FROM   pedidos
        WHERE  fecha_hora_pedido BETWEEN %s AND %s
          AND  total <= %s
          AND  estado_pedido = %s
        ORDER BY fecha_hora_pedido;
    """
    df = pd.read_sql(sql, conn,
                     params=[fecha_ini, fecha_fin, monto_max, estado_sel])
    tabla_y_descarga(df, "pedidos_filtrados")

    if not df.empty:
        pdf_bytes = df_to_pdf_bytes(df, "Pedidos filtrados")
        st.download_button("📄 Descargar PDF",
                           data=pdf_bytes,
                           file_name="pedidos_filtrados.pdf",
                           mime="application/pdf",
                           key="pdf_pedidos_detalle"
                           )


# REPORTE 2 – Ventas por día -------------------------------------------------------------------
with tab2:
    st.header("Ventas por día")
    sql = """
        SELECT fecha_hora_pedido::date AS fecha,
               SUM(total) AS ventas
        FROM   pedidos
        WHERE  fecha_hora_pedido BETWEEN %s AND %s
        GROUP  BY 1
        ORDER  BY 1;
    """
    df = pd.read_sql(sql, conn, params=[fecha_ini, fecha_fin])
    tabla_y_descarga(df, "ventas_por_dia")

    # Gráfica
    fig, ax = plt.subplots()
    ax.plot(df["fecha"], df["ventas"], marker="o")
    ax.set_xlabel("Fecha")
    ax.set_ylabel("Ventas (Q)")
    ax.set_title("Ventas por día")
    st.pyplot(fig)

    if not df.empty:
        pdf_bytes = df_to_pdf_bytes(df, "Ventas por día", fig)
        st.download_button(
            "📄 Descargar PDF",
            data=pdf_bytes,
            file_name="ventas_por_dia.pdf",
            mime="application/pdf",
            key="pdf_ventas_dia"
        )



# REPORTE 3 – Ingresos por método --------------------------------------------------------------
with tab3:
    st.header("Ingresos por método de pago")
    sql = """
        SELECT metodo_pago,
               SUM(monto) AS total_ingresos
        FROM   pagos
        WHERE  fecha_pago BETWEEN %s AND %s
        GROUP  BY 1;
    """
    df = pd.read_sql(sql, conn, params=[fecha_ini, fecha_fin])
    tabla_y_descarga(df, "ingresos_por_metodo")

    fig, ax = plt.subplots()
    ax.bar(df["metodo_pago"], df["total_ingresos"])
    ax.set_xlabel("Método de pago")
    ax.set_ylabel("Ingresos (Q)")
    st.pyplot(fig)

    if not df.empty:
        pdf_bytes = df_to_pdf_bytes(df, "Ingresos por método", fig)
        st.download_button(
            "📄 Descargar PDF",
            data=pdf_bytes,
            file_name="ingresos_por_metodo.pdf",
            mime="application/pdf",
            key="pdf_ingresos_por_metodo"
        )



# REPORTE 4 – Top 10 productos -----------------------------------------------------------------
with tab4:
    st.header("Top 10 productos más vendidos")
    cond_cat, params_cat = condicion_categoria("p")

    sql = f"""
        SELECT p.nombre_producto,
               SUM(i.cantidad) AS unidades
        FROM   items_orden i
        JOIN   productos p USING(id_producto)
        WHERE  i.fecha_registro BETWEEN %s AND %s
        {cond_cat}
        GROUP  BY p.nombre_producto
        ORDER  BY 2 DESC
        LIMIT 10;
    """
    df = pd.read_sql(sql, conn, params=[fecha_ini, fecha_fin, *params_cat])

    tabla_y_descarga(df, "top10_productos")

    fig, ax = plt.subplots()
    ax.barh(df["nombre_producto"], df["unidades"])
    ax.invert_yaxis()
    ax.set_xlabel("Unidades vendidas")
    st.pyplot(fig)

    if not df.empty:
        pdf_bytes = df_to_pdf_bytes(df, "Productos más Vendidos", fig)
        st.download_button(
            "📄 Descargar PDF",
            data=pdf_bytes,
            file_name="productos_mas_vendidos.pdf",
            mime="application/pdf",
            key="pdf_productos_mas_vendidos"
        )



# REPORTE 5 – Pedidos abiertos -----------------------------------------------------------------
with tab5:
    st.header("Pedidos abiertos")
    sql = """
        SELECT id_pedido,
               fecha_hora_pedido,
               total
        FROM   pedidos
        WHERE  estado_pedido = 'abierta';
    """
    df = pd.read_sql(sql, conn)
    tabla_y_descarga(df, "pedidos_abiertos")

    if not df.empty:
        pdf_bytes = df_to_pdf_bytes(df, "Pedidos abiertos")
        st.download_button(
            "📄 Descargar PDF",
            data=pdf_bytes,
            file_name="pedidos_abiertos.pdf",
            mime="application/pdf",
            key="pdf_pedidos_abiertos"
        )
 




# para ejecutar
# streamlit run Cafeteria.py
