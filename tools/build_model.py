"""Generates the Power BI semantic model (TMDL) for RetailDashboard.

Run:  python tools/build_model.py   (writes powerbi/RetailDashboard.SemanticModel)
"""
import os, uuid, json, shutil

ROOT = os.path.join(os.path.dirname(__file__), "..", "powerbi")
SM = os.path.join(ROOT, "RetailDashboard.SemanticModel")
DEF = os.path.join(SM, "definition")

def tag(name):  # stable lineage tags, so regenerating doesn't break the report
    return str(uuid.uuid5(uuid.NAMESPACE_URL, "retaildwh/" + name))

def w(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)

# ------------------------------------------------------------------ tables
# (name, sql view, [(column, dataType, hidden, format)])
I, S, D, T, B = "int64", "string", "double", "dateTime", "boolean"
TABLES = [
    ("Date", "dim_date", [
        ("date_key", I, True, None), ("full_date", T, False, "yyyy-mm-dd"), ("day_of_week", I, True, None),
        ("day_name", S, False, None), ("day_of_month", I, False, None), ("day_of_year", I, True, None),
        ("week_of_year", I, False, None), ("month_number", I, True, None), ("month_name", S, False, None),
        ("quarter", I, False, None), ("year", I, False, None), ("is_weekend", B, False, None),
        ("year_month", I, True, None), ("month_short", S, True, None), ("year_quarter", I, True, None)]),
    ("Customer", "dim_customer", [
        ("customer_key", I, True, None), ("customer_id", I, False, None), ("full_name", S, False, None),
        ("gender", S, False, None), ("city", S, False, None), ("loyalty_level", S, False, None),
        ("email", S, False, None), ("is_email_shared", B, False, None), ("customer_label", S, False, None)]),
    ("Product", "dim_product", [
        ("product_key", I, True, None), ("product_id", I, False, None), ("sku", S, False, None),
        ("product_name", S, False, None), ("brand_name", S, False, None), ("department_name", S, False, None),
        ("package_size", S, False, None), ("brand_id", I, True, None), ("department_id", I, True, None)]),
    ("Promotion", "dim_promotion", [
        ("promotion_key", I, True, None), ("promotion_id", I, False, None), ("promo_type", S, False, None),
        ("discount_percent", D, False, "0"), ("start_date", T, False, "yyyy-mm-dd"), ("end_date", T, False, "yyyy-mm-dd"),
        ("is_discount_missing", B, False, None), ("is_dates_swapped", B, False, None)]),
    ("Store", "dim_store", [
        ("store_key", I, True, None), ("store_id", I, False, None), ("store_name", S, False, None),
        ("city", S, False, None), ("state", S, False, None), ("region", S, False, None),
        ("opening_date", T, False, "yyyy-mm-dd")]),
    ("Employee", "dim_employee", [
        ("employee_key", I, True, None), ("employee_id", I, False, None), ("full_name", S, False, None),
        ("gender", S, False, None), ("position", S, False, None), ("store_id", I, False, None),
        ("hire_date", T, False, "yyyy-mm-dd")]),
    ("Warehouse", "dim_warehouse", [
        ("warehouse_key", I, True, None), ("warehouse_id", I, False, None), ("warehouse_name", S, False, None),
        ("city", S, False, None), ("state", S, False, None)]),
    ("Delivery Provider", "dim_delivery_provider", [
        ("delivery_provider_key", I, True, None), ("provider_id", I, False, None),
        ("provider_name", S, False, None), ("phone", S, False, None)]),
    ("Online Sales", "fact_online_sales", [
        ("online_sales_key", I, True, None), ("order_date_key", I, True, None), ("delivery_date_key", I, True, None),
        ("customer_key", I, True, None), ("product_key", I, True, None), ("promotion_key", I, True, None),
        ("warehouse_key", I, True, None), ("delivery_provider_key", I, True, None), ("order_id", I, False, None),
        ("order_status", S, False, None), ("delivery_status", S, False, None), ("payment_method", S, False, None),
        ("quantity", I, False, None), ("unit_price", D, False, "\\$#,0.00"), ("discount_percent", D, False, "0"),
        ("gross_amount", D, False, "\\$#,0.00"), ("discount_amount", D, False, "\\$#,0.00"),
        ("net_amount", D, False, "\\$#,0.00"), ("delivery_days", I, False, None),
        ("order_status_source", S, False, None), ("days_to_ship", I, False, None),
        ("is_delivery_date_invalid", B, False, None), ("quantity_source", S, False, None),
        ("price_source", S, False, None)]),
    ("Store Sales", "fact_pos_sales", [
        ("pos_sales_key", I, True, None), ("date_key", I, True, None), ("customer_key", I, True, None),
        ("product_key", I, True, None), ("promotion_key", I, True, None), ("store_key", I, True, None),
        ("employee_key", I, True, None), ("transaction_id", S, False, None), ("quantity", I, False, None),
        ("unit_price", D, False, "\\$#,0.00"), ("discount_percent", D, False, "0"),
        ("gross_amount", D, False, "\\$#,0.00"), ("discount_amount", D, False, "\\$#,0.00"),
        ("net_amount", D, False, "\\$#,0.00"), ("register_id", I, True, None),
        ("quantity_source", S, False, None), ("price_source", S, False, None)]),
]


SPECIAL = {"customer_label": "Customer", "full_name": "Name", "provider_name": "Provider",
           "warehouse_name": "Warehouse", "store_name": "Store", "product_name": "Product",
           "brand_name": "Brand", "department_name": "Department", "promo_type": "Promotion Type",
           "month_name": "Month Name", "day_name": "Day Name", "sku": "SKU", "is_email_shared": "Email Shared",
           "is_discount_missing": "Discount Missing", "is_dates_swapped": "Dates Swapped",
           "is_delivery_date_invalid": "Delivery Date Invalid", "is_weekend": "Is Weekend",
           "order_status_source": "Order Status (Source)", "full_date": "Date"}

def nice(col, hidden=False):
    """Business-friendly column name. Hidden technical columns keep their SQL name."""
    if hidden:
        return col
    return SPECIAL.get(col, col.replace("_", " ").title().replace(" Id", " ID"))

def colname(c):
    return f"'{c}'" if (" " in c or "(" in c) else c

HIDDEN = {}
def _index():
    for t, _, cols in TABLES:
        for c, dt, hid, fmt in cols:
            HIDDEN[(t, c)] = hid
def ref_fix(expr):
    """Rewrite 'Table'[raw_col] references to the friendly column names."""
    if not HIDDEN:
        _index()
    for (t, c), hid in HIDDEN.items():
        new = nice(c, hid)
        for tref in (f"'{t}'", t):
            expr = expr.replace(f"{tref}[{c}]", f"{tref}[{new}]")
    return expr

# Calculated columns: table -> [(name, expression, sortBy)]
CALC = {
    "Date": [("Month", "'Date'[month_short] & \" \" & 'Date'[year]", "year_month"),
             ("Quarter Label", "\"Q\" & 'Date'[quarter] & \" \" & 'Date'[year]", "year_quarter")],
}
SORT_BY = {("Date", "month_name"): "month_number", ("Date", "day_name"): "day_of_week"}

def q(name):
    return f"'{name}'" if (" " in name or name in ("Date",)) else name

def table_tmdl(name, view, cols):
    if not HIDDEN:
        _index()
    out = [f"table {q(name)}", f"\tlineageTag: {tag(name)}"]
    if name == "Date":
        out.append("\tdataCategory: Time")
    out.append("")
    for c, dt, hidden, fmt in cols:
        out.append(f"\tcolumn {colname(nice(c, hidden))}")
        out.append(f"\t\tdataType: {dt}")
        if name == "Date" and c == "full_date":
            out.append("\t\tisKey")
        if hidden:
            out.append("\t\tisHidden")
        if fmt:
            out.append(f"\t\tformatString: {fmt}")
        elif dt == I:
            out.append("\t\tformatString: 0")
        out.append(f"\t\tlineageTag: {tag(name + '.' + c)}")
        out.append("\t\tsummarizeBy: none")
        out.append(f"\t\tsourceColumn: {c}")
        if (name, c) in SORT_BY:
            out.append(f"\t\tsortByColumn: {colname(nice(SORT_BY[(name, c)], HIDDEN.get((name, SORT_BY[(name, c)]), True)))}")
        if dt == T:
            out.append("")
            out.append("\t\tannotation UnderlyingDateTimeDataType = Date")
        out.append("")
        out.append("\t\tannotation SummarizationSetBy = User")
        out.append("")
    for cname, expr, sort in CALC.get(name, []):
        out.append(f"\tcolumn {q(cname)} = {ref_fix(expr)}")
        out.append(f"\t\tlineageTag: {tag(name + '.' + cname)}")
        out.append("\t\tsummarizeBy: none")
        if sort:
            out.append(f"\t\tsortByColumn: {colname(nice(sort, HIDDEN.get((name, sort), True)))}")
        out.append("")
        out.append("\t\tannotation SummarizationSetBy = User")
        out.append("")
    # Partition: read the gold view; the Date table drops the 1900 "Unknown" row
    # so it stays a contiguous calendar (required to mark it as a date table).
    step = f'Source{{[Schema="gold",Item="{view}"]}}[Data]'
    lines = ["let", "    Source = Sql.Database(Server, Database),", f"    Data = {step}"]
    if name == "Date":
        lines[-1] += ","
        lines.append("    Calendar = Table.SelectRows(Data, each [date_key] <> 19000101)")
        lines += ["in", "    Calendar"]
    else:
        lines += ["in", "    Data"]
    out.append(f"\tpartition {q(name)} = m")
    out.append("\t\tmode: import")
    out.append("\t\tsource =")
    out += ["\t\t\t\t" + l for l in lines]
    out.append("")
    out.append("\tannotation PBI_ResultType = Table")
    out.append("")
    return "\n".join(out)

# ---------------------------------------------------------------- measures
ON, ST = "'Online Sales'", "'Store Sales'"
CUR, CUR2, PCT, INT, DEC1 = "\\$#,0", "\\$#,0.00", "0.0%", "#,0", "0.0"
MEASURES = [
    # (folder, name, expression, format, description)
    ("Revenue", "Online Revenue", f'CALCULATE ( SUM ( {ON}[net_amount] ), {ON}[order_status] <> "Cancelled" )', CUR,
     "Online net revenue, excluding cancelled orders."),
    ("Revenue", "Store Revenue", f"SUM ( {ST}[net_amount] )", CUR, "In-store (POS) net revenue."),
    ("Revenue", "Total Revenue", "[Online Revenue] + [Store Revenue]", CUR, "Online (excl. cancelled) + store net revenue."),
    ("Revenue", "Revenue YoY %",
     "VAR LatestYear = MAXX ( FILTER ( VALUES ( 'Date'[year] ), [Total Revenue] > 0 ), 'Date'[year] )\n"
     "VAR Cur = CALCULATE ( [Total Revenue], 'Date'[year] = LatestYear )\n"
     "VAR Prev = CALCULATE ( [Total Revenue], 'Date'[year] = LatestYear - 1 )\n"
     "RETURN DIVIDE ( Cur - Prev, Prev )", PCT,
     "Growth of the latest year in the selection versus the year before (same months)."),
    ("Revenue", "Online Share %", "DIVIDE ( [Online Revenue], [Total Revenue] )", PCT, "Share of revenue from online."),
    ("Revenue", "Discount Given",
     f'SUM ( {ST}[discount_amount] ) + CALCULATE ( SUM ( {ON}[discount_amount] ), {ON}[order_status] <> "Cancelled" )', CUR,
     "Discount amount given in both channels."),
    ("Revenue", "Promo Revenue", "CALCULATE ( [Total Revenue], Promotion[promotion_key] <> -1 )", CUR,
     "Revenue from lines sold with a promotion."),
    ("Revenue", "Promo Revenue %", "DIVIDE ( [Promo Revenue], [Total Revenue] )", PCT, "Share of revenue sold on promotion."),
    ("Orders", "Online Orders", f'CALCULATE ( DISTINCTCOUNT ( {ON}[order_id] ), {ON}[order_status] <> "Cancelled" )', INT,
     "Online orders, excluding cancelled."),
    ("Orders", "All Online Orders", f"DISTINCTCOUNT ( {ON}[order_id] )", INT, "Every online order, any status."),
    ("Orders", "Store Transactions", f"DISTINCTCOUNT ( {ST}[transaction_id] )", INT, "In-store transactions."),
    ("Orders", "Total Orders", "[Online Orders] + [Store Transactions]", INT, "Online orders + store transactions."),
    ("Orders", "Avg Order Value", "DIVIDE ( [Total Revenue], [Total Orders] )", CUR2, "Revenue per order, both channels."),
    ("Orders", "Avg Basket (Store)", "DIVIDE ( [Store Revenue], [Store Transactions] )", CUR2, "Revenue per store transaction."),
    ("Orders", "Units Sold",
     f'SUM ( {ST}[quantity] ) + CALCULATE ( SUM ( {ON}[quantity] ), {ON}[order_status] <> "Cancelled" )', INT,
     "Units sold in both channels."),
    ("Customers", "Active Customers",
     f"COUNTROWS ( DISTINCT ( UNION ( VALUES ( {ST}[customer_key] ), VALUES ( {ON}[customer_key] ) ) ) )", INT,
     "Customers who bought in either channel."),
    ("Customers", "Online Customers", f"DISTINCTCOUNT ( {ON}[customer_key] )", INT, "Customers with an online order."),
    ("Customers", "Store Customers", f"DISTINCTCOUNT ( {ST}[customer_key] )", INT, "Customers with a store purchase."),
    ("Customers", "Revenue per Customer", "DIVIDE ( [Total Revenue], [Active Customers] )", CUR2, "Revenue per active customer."),
    ("Delivery", "Cancelled Orders", f'CALCULATE ( DISTINCTCOUNT ( {ON}[order_id] ), {ON}[order_status] = "Cancelled" )', INT, ""),
    ("Delivery", "Returned Orders", f'CALCULATE ( DISTINCTCOUNT ( {ON}[order_id] ), {ON}[order_status] = "Returned" )', INT, ""),
    ("Delivery", "Shipped Orders", f'CALCULATE ( DISTINCTCOUNT ( {ON}[order_id] ), {ON}[delivery_status] <> "Not Shipped" )', INT,
     "Orders that left the warehouse."),
    ("Delivery", "Delivered Orders", f'CALCULATE ( DISTINCTCOUNT ( {ON}[order_id] ), {ON}[delivery_status] = "Delivered" )', INT, ""),
    ("Delivery", "Delivery Rate %", "DIVIDE ( [Delivered Orders], [Shipped Orders] )", PCT, "Delivered orders as a share of shipped orders."),
    ("Delivery", "Cancellation Rate %", "DIVIDE ( [Cancelled Orders], [All Online Orders] )", PCT, ""),
    ("Delivery", "Return Rate %", "DIVIDE ( [Returned Orders], [All Online Orders] )", PCT, ""),
    ("Delivery", "Avg Delivery Days", f"AVERAGE ( {ON}[delivery_days] )", DEC1, "Days from shipping to delivery (delivered orders)."),
    ("Delivery", "Avg Days to Ship", f"AVERAGE ( {ON}[days_to_ship] )", DEC1, "Days from order to shipping."),
    ("Delivery", "Deliveries by Delivery Date",
     f"CALCULATE ( [Delivered Orders], USERELATIONSHIP ( {ON}[delivery_date_key], 'Date'[date_key] ) )", INT,
     "Delivered orders counted on the day they arrived."),
]

def measures_tmdl():
    out = ["table 'Key Measures'", f"\tlineageTag: {tag('Measures')}", ""]
    for folder, name, expr, fmt, desc in MEASURES:
        expr = ref_fix(expr)
        lines = expr.split("\n")
        if len(lines) == 1:
            out.append(f"\tmeasure {q(name) if ' ' in name or '%' in name or '(' in name else name} = {expr}")
        else:
            out.append(f"\tmeasure '{name}' =")
            out += ["\t\t\t" + l for l in lines]
        out.append(f"\t\tformatString: {fmt}")
        out.append(f"\t\tdisplayFolder: {folder}")
        out.append(f"\t\tlineageTag: {tag('m.' + name)}")
        out.append("")
    out.append("\tcolumn Column1")
    out.append("\t\tdataType: string")
    out.append("\t\tisHidden")
    out.append(f"\t\tlineageTag: {tag('Measures.Column1')}")
    out.append("\t\tsummarizeBy: none")
    out.append("\t\tsourceColumn: Column1")
    out.append("")
    out.append("\t\tannotation SummarizationSetBy = Automatic")
    out.append("")
    out.append("\tpartition 'Key Measures' = m")
    out.append("\t\tmode: import")
    out.append("\t\tsource =")
    out.append("\t\t\t\tlet")
    out.append('\t\t\t\t    Source = #table(type table [Column1 = text], {})')
    out.append("\t\t\t\tin")
    out.append("\t\t\t\t    Source")
    out.append("")
    out.append("\tannotation PBI_ResultType = Table")
    out.append("")
    return "\n".join(out)

# ----------------------------------------------------------- relationships
REL = [  # (from table, from column, to table, to column, active)
    ("Online Sales", "order_date_key", "Date", "date_key", True),
    ("Online Sales", "delivery_date_key", "Date", "date_key", False),
    ("Online Sales", "customer_key", "Customer", "customer_key", True),
    ("Online Sales", "product_key", "Product", "product_key", True),
    ("Online Sales", "promotion_key", "Promotion", "promotion_key", True),
    ("Online Sales", "warehouse_key", "Warehouse", "warehouse_key", True),
    ("Online Sales", "delivery_provider_key", "Delivery Provider", "delivery_provider_key", True),
    ("Store Sales", "date_key", "Date", "date_key", True),
    ("Store Sales", "customer_key", "Customer", "customer_key", True),
    ("Store Sales", "product_key", "Product", "product_key", True),
    ("Store Sales", "promotion_key", "Promotion", "promotion_key", True),
    ("Store Sales", "store_key", "Store", "store_key", True),
    ("Store Sales", "employee_key", "Employee", "employee_key", True),
]

def relationships_tmdl():
    out = []
    for ft, fc, tt, tc, active in REL:
        out.append(f"relationship {tag('rel.' + ft + fc)}")
        if not active:
            out.append("\tisActive: false")
        out.append(f"\tfromColumn: {q(ft)}.{fc}")
        out.append(f"\ttoColumn: {q(tt)}.{tc}")
        out.append("")
    return "\n".join(out)

def build():
    if os.path.isdir(SM):
        shutil.rmtree(SM)
    w(os.path.join(DEF, "database.tmdl"), "database\n\tcompatibilityLevel: 1606\n\n")
    names = [t[0] for t in TABLES] + ["Key Measures"]
    model = ["model Model", "\tculture: en-US", "\tdefaultPowerBIDataSourceVersion: powerBI_V3",
             "\tdiscourageImplicitMeasures", "\tsourceQueryCulture: en-US", "\tdataAccessOptions",
             "\t\tlegacyRedirects", "\t\treturnErrorValuesAsNull", "",
             "annotation __PBI_TimeIntelligenceEnabled = 0", "",
             "annotation PBI_QueryOrder = " + json.dumps(["Server", "Database"] + names), "",
             "annotation PBI_ProTooling = [\"DevMode\"]", ""]
    model += [f"ref table {q(n)}" for n in names]
    model += ["", "ref cultureInfo en-US", ""]
    w(os.path.join(DEF, "model.tmdl"), "\n".join(model) + "\n")
    w(os.path.join(DEF, "cultures", "en-US.tmdl"), "cultureInfo en-US\n\n")
    exprs = []
    for pname, val in (("Server", "localhost"), ("Database", "RetailDWH")):
        exprs += [f'expression {pname} = "{val}" meta [IsParameterQuery=true, Type="Text", IsParameterQueryRequired=true]',
                  f"\tlineageTag: {tag('param.' + pname)}", "",
                  "\tannotation PBI_ResultType = Text", ""]
    w(os.path.join(DEF, "expressions.tmdl"), "\n".join(exprs) + "\n")
    w(os.path.join(DEF, "relationships.tmdl"), relationships_tmdl() + "\n")
    for name, view, cols in TABLES:
        w(os.path.join(DEF, "tables", f"{name}.tmdl"), table_tmdl(name, view, cols))
    # file keeps the name Measures.tmdl (TMDL reads the table name from the file content)
    w(os.path.join(DEF, "tables", "Measures.tmdl"), measures_tmdl())
    w(os.path.join(SM, "definition.pbism"), json.dumps({"version": "4.2", "settings": {}}, indent=2) + "\n")
    w(os.path.join(SM, ".platform"), json.dumps({
        "$schema": "https://developer.microsoft.com/json-schemas/fabric/gitIntegration/platformProperties/2.0.0/schema.json",
        "metadata": {"type": "SemanticModel", "displayName": "RetailDashboard"},
        "config": {"version": "2.0", "logicalId": tag("semanticmodel")}}, indent=2) + "\n")
    print("model written:", len(TABLES) + 1, "tables,", len(MEASURES), "measures,", len(REL), "relationships")

if __name__ == "__main__":
    build()
