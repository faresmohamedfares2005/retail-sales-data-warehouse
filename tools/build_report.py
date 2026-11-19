"""Generates the Power BI report (PBIR) for RetailDashboard: theme + 5 pages.

Run:  python tools/build_report.py   (writes powerbi/RetailDashboard.Report and RetailDashboard.pbip)
"""
import os, json, uuid, shutil, sys
sys.path.insert(0, os.path.dirname(__file__))
import build_model as M
M._index()

HERE = os.path.dirname(__file__)
ROOT = os.path.join(HERE, "..", "powerbi")
RPT = os.path.join(ROOT, "RetailDashboard.Report")
DEF = os.path.join(RPT, "definition")
BASE_THEME_SRC = os.path.join(HERE, "CY26SU04.json")

SCHEMA = "https://developer.microsoft.com/json-schemas/fabric/item/report/definition"
NAVY, BLUE, TEAL, ORANGE, GREEN, RED = "#14365D", "#2563EB", "#0EA5A4", "#F59E0B", "#16A34A", "#DC2626"
INK, MUTED, LINE, PAGE_BG = "#111827", "#6B7280", "#E5E7EB", "#F3F5F9"

def uid(*parts):
    return uuid.uuid5(uuid.NAMESPACE_URL, "retaildwh-report/" + "/".join(parts)).hex[:20]

def w(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(obj, indent=2, ensure_ascii=False) if not isinstance(obj, str) else obj)

def lit(v):
    return {"expr": {"Literal": {"Value": v}}}

def s(text):            # string literal
    return lit("'" + text.replace("'", "''") + "'")

def color(hexc):
    return {"solid": {"color": lit("'" + hexc + "'")}}

def col(entity, prop):
    prop = M.nice(prop, M.HIDDEN.get((entity, prop), False))
    return {"Column": {"Expression": {"SourceRef": {"Entity": entity}}, "Property": prop}}

def mea(prop):
    return {"Measure": {"Expression": {"SourceRef": {"Entity": "Key Measures"}}, "Property": prop}}

def proj(field, active=False):
    kind = "Column" if "Column" in field else "Measure"
    ent = field[kind]["Expression"]["SourceRef"]["Entity"]
    prop = field[kind]["Property"]
    p = {"field": field, "queryRef": f"{ent}.{prop}", "nativeQueryRef": prop}
    if active:
        p["active"] = True
    return p

def title_obj(text, show=True, size=11):
    props = {"show": lit("true" if show else "false")}
    if show:
        props.update({"text": s(text), "fontSize": lit(f"{size}D"), "fontColor": color(INK), "bold": lit("true")})
    return [{"properties": props}]

def container(title=None, bg="#FFFFFF", border=True, radius=10, padding=None):
    o = {"title": title_obj(title) if title else title_obj("", show=False),
         "background": [{"properties": {"show": lit("true"), "color": color(bg), "transparency": lit("0D")}}],
         "border": [{"properties": {"show": lit("true" if border else "false"), "color": color(LINE),
                                     "radius": lit(f"{radius}D")}}],
         "dropShadow": [{"properties": {"show": lit("false")}}],
         "visualHeader": [{"properties": {"show": lit("false")}}]}
    if padding is not None:
        o["padding"] = [{"properties": {"top": lit(f"{padding}D"), "bottom": lit(f"{padding}D"),
                                        "left": lit(f"{padding}D"), "right": lit(f"{padding}D")}}]
    return o

def topn_filter(entity, prop, measure, n=10):
    prop = M.nice(prop, M.HIDDEN.get((entity, prop), False))
    return {"filters": [{
        "name": uid("topn", entity, prop, measure),
        "field": {"Column": {"Expression": {"SourceRef": {"Entity": entity}}, "Property": prop}},
        "type": "TopN",
        "filter": {"Version": 2,
                   "From": [{"Name": "subquery", "Expression": {"Subquery": {"Query": {
                       "Version": 2,
                       "From": [{"Name": "d", "Entity": entity, "Type": 0}, {"Name": "m", "Entity": "Key Measures", "Type": 0}],
                       "Select": [{"Column": {"Expression": {"SourceRef": {"Source": "d"}}, "Property": prop}, "Name": "field"}],
                       "OrderBy": [{"Direction": 2, "Expression": {"Measure": {"Expression": {"SourceRef": {"Source": "m"}}, "Property": measure}}}],
                       "Top": n}}}, "Type": 2},
                            {"Name": "d", "Entity": entity, "Type": 0}],
                   "Where": [{"Condition": {"In": {"Expressions": [{"Column": {"Expression": {"SourceRef": {"Source": "d"}}, "Property": prop}}],
                                                   "Table": {"SourceRef": {"Source": "subquery"}}}}}]}}]}

class Page:
    def __init__(self, key, name, subtitle):
        self.key, self.name, self.subtitle = key, name, subtitle
        self.visuals, self.z = [], 1000

    def add(self, vid, x, y, wd, ht, visual, filters=None):
        self.z += 1000
        v = {"$schema": f"{SCHEMA}/visualContainer/2.12.0/schema.json",
             "name": uid(self.key, vid),
             "position": {"x": x, "y": y, "z": self.z, "height": ht, "width": wd, "tabOrder": self.z},
             "visual": visual}
        if filters:
            v["filterConfig"] = filters
        self.visuals.append(v)

    # ---------- building blocks
    def textbox(self, vid, x, y, wd, ht, runs, bg=None, align="left"):
        paragraphs = [{"textRuns": [{"value": t, "textStyle": st} for t, st in line],
                       "horizontalTextAlignment": align} for line in runs]
        vco = {"background": [{"properties": {"show": lit("true" if bg else "false"),
                                              **({"color": color(bg), "transparency": lit("0D")} if bg else {})}}],
               "border": [{"properties": {"show": lit("false")}}],
               "dropShadow": [{"properties": {"show": lit("false")}}],
               "visualHeader": [{"properties": {"show": lit("false")}}],
               "title": title_obj("", show=False)}
        self.add(vid, x, y, wd, ht, {"visualType": "textbox",
                                    "objects": {"general": [{"properties": {"paragraphs": paragraphs}}]},
                                    "visualContainerObjects": vco, "drillFilterOtherVisuals": True})

    def card(self, vid, x, y, wd, ht, measure, label=None, accent=NAVY):
        big_money = any(k in measure for k in ("Revenue", "Discount Given")) and "%" not in measure and "per" not in measure
        objs = {"labels": [{"properties": {"color": color(accent), "fontSize": lit("20D"), "bold": lit("true"),
                                           "labelDisplayUnits": lit("0D"),
                                           **({"labelPrecision": lit("2D")} if big_money else {})}}],
                "categoryLabels": [{"properties": {"show": lit("true"), "color": color(MUTED), "fontSize": lit("9D")}}]}
        vis = {"visualType": "card",
               "query": {"queryState": {"Values": {"projections": [proj(mea(measure))]}}},
               "objects": objs,
               "visualContainerObjects": container(None, padding=4), "drillFilterOtherVisuals": True}
        self.add(vid, x, y, wd, ht, vis)

    def chart(self, vid, x, y, wd, ht, vtype, title, category, measures, series=None,
              sort_by=None, sort_dir="Descending", filters=None, legend=False, labels=True, colors=None):
        qs = {"Category": {"projections": [proj(category, active=True)]},
              "Y": {"projections": [proj(m) for m in measures]}}
        if series:
            qs["Series"] = {"projections": [proj(series)]}
        query = {"queryState": qs}
        if sort_by is not None:
            query["sortDefinition"] = {"sort": [{"field": sort_by, "direction": sort_dir}], "isDefaultSort": True}
        objs = {"legend": [{"properties": {"show": lit("true" if legend else "false"), "position": s("Top"),
                                           "fontSize": lit("9D")}}],
                "labels": [{"properties": {"show": lit("true" if labels else "false"), "fontSize": lit("8D"),
                                           "labelDisplayUnits": lit("0D")}}],
                "categoryAxis": [{"properties": {"showAxisTitle": lit("false"), "fontSize": lit("9D")}}],
                "valueAxis": [{"properties": {"showAxisTitle": lit("false"), "show": lit("false" if labels and vtype != 'lineChart' else "true"),
                                              "gridlineShow": lit("false" if labels and vtype != 'lineChart' else "true")}}]}
        if colors and len(measures) == 1 and vtype != "donutChart":
            objs["dataPoint"] = [{"properties": {"fill": color(colors[0])}}]
        elif colors:
            dp = []
            for i, (m, c) in enumerate(zip(measures, colors)):
                kind = "Measure"
                dp.append({"properties": {"fill": color(c)},
                           "selector": {"metadata": f"Key Measures.{m[kind]['Property']}"}})
            objs["dataPoint"] = dp
        if vtype == "donutChart":
            objs = {"legend": [{"properties": {"show": lit("true"), "position": s("Right"), "fontSize": lit("9D")}}],
                    "labels": [{"properties": {"show": lit("true"), "labelStyle": s("Percent of total"), "fontSize": lit("9D")}}]}
        if vtype == "lineChart":
            objs["lineStyles"] = [{"properties": {"strokeWidth": lit("3D"), "showMarker": lit("true")}}]
            objs["labels"] = [{"properties": {"show": lit("false")}}]
        vis = {"visualType": vtype, "query": query, "objects": objs,
               "visualContainerObjects": container(title, padding=8), "drillFilterOtherVisuals": True}
        self.add(vid, x, y, wd, ht, vis, filters)

    def table(self, vid, x, y, wd, ht, title, fields, sort_by, filters=None):
        first = 0.34 if len(fields) > 3 else 0.4
        widths = [(wd - 40) * first] + [(wd - 40) * (1 - first) / (len(fields) - 1)] * (len(fields) - 1)
        colw = [{"properties": {"value": lit(f"{w:.0f}D")},
                 "selector": {"metadata": proj(f)["queryRef"]}} for f, w in zip(fields, widths)]
        vis = {"visualType": "tableEx",
               "query": {"queryState": {"Values": {"projections": [proj(f) for f in fields]}},
                         "sortDefinition": {"sort": [{"field": sort_by, "direction": "Descending"}], "isDefaultSort": True}},
               "objects": {"grid": [{"properties": {"gridVertical": lit("false"), "rowPadding": lit("4D"),
                                                    "textSize": lit("9D"), "gridHorizontalColor": color(LINE)}}],
                           "columnHeaders": [{"properties": {"fontColor": color("#FFFFFF"), "backColor": color(NAVY),
                                                             "fontSize": lit("9D"), "bold": lit("true")}}],
                           "values": [{"properties": {"fontSize": lit("9D"), "backColorSecondary": color("#F8FAFC")}}],
                           "total": [{"properties": {"totals": lit("false")}}],
                           "columnWidth": colw},
               "visualContainerObjects": container(title, padding=8), "drillFilterOtherVisuals": True}
        self.add(vid, x, y, wd, ht, vis, filters)

    def slicer(self, vid, x, y, wd, ht, field, title, sync=None):
        vis = {"visualType": "slicer",
               "query": {"queryState": {"Values": {"projections": [proj(field, active=True)]}}},
               "objects": {"data": [{"properties": {"mode": s("Dropdown")}}],
                           "header": [{"properties": {"show": lit("true"), "fontColor": color(MUTED), "textSize": lit("9D"),
                                                      "text": s(title)}}],
                           "items": [{"properties": {"textSize": lit("10D")}}],
                           "selection": [{"properties": {"selectAllCheckboxEnabled": lit("true"),
                                                         "singleSelect": lit("false")}}]},
               "visualContainerObjects": {"title": title_obj("", show=False),
                                          "background": [{"properties": {"show": lit("false")}}],
                                          "border": [{"properties": {"show": lit("false")}}],
                                          "visualHeader": [{"properties": {"show": lit("false")}}]},
               "drillFilterOtherVisuals": True}
        if sync:
            vis["syncGroup"] = {"groupName": sync, "fieldChanges": True, "filterChanges": True}
        self.add(vid, x, y, wd, ht, vis)

    def write(self):
        pdir = os.path.join(DEF, "pages", self.key)
        w(os.path.join(pdir, "page.json"), {
            "$schema": f"{SCHEMA}/page/2.1.0/schema.json", "name": self.key, "displayName": self.name,
            "displayOption": "FitToPage", "height": 720, "width": 1280})
        for v in self.visuals:
            w(os.path.join(pdir, "visuals", v["name"], "visual.json"), v)

# ------------------------------------------------------------- layout grid
W, H = 1280, 720
PANEL_X, PANEL_W = 16, 196
CX, CW = 228, W - 228 - 16           # content area: x 228 .. 1264
KPI_Y, KPI_H = 72, 84
R1_Y, R1_H = 168, 266
R2_Y, R2_H = 446, 262
GAP = 12

def cols(n, x=CX, width=CW):
    cw = (width - GAP * (n - 1)) / n
    return [(x + i * (cw + GAP), cw) for i in range(n)]

PAGES_ORDER = ["overview", "customers", "products", "online", "stores"]
NAV = {"overview": "Overview", "customers": "Customers", "products": "Products & Promotions",
       "online": "Online & Delivery", "stores": "Store Performance"}

def chrome(p, extra_slicers):
    """Header bar, left filter panel with shared + page slicers, footer note."""
    p.textbox("header", 0, 0, W, 56, [[(p.name, {"fontSize": "18pt", "fontWeight": "bold", "color": "#FFFFFF",
                                                 "fontFamily": "Segoe UI Semibold"}),
                                        ("   |   " + p.subtitle, {"fontSize": "11pt", "color": "#C7D2E3",
                                                                  "fontFamily": "Segoe UI"})]], bg=NAVY)
    p.textbox("brand", W - 300, 0, 290, 56, [[("Retail Sales Analytics", {"fontSize": "10pt", "color": "#C7D2E3",
                                                                          "fontFamily": "Segoe UI"})]], align="right")
    p.textbox("panel", PANEL_X, KPI_Y, PANEL_W, H - KPI_Y - 12,
              [[("FILTERS", {"fontSize": "9pt", "fontWeight": "bold", "color": MUTED, "fontFamily": "Segoe UI Semibold"})]],
              bg="#FFFFFF")
    slicers = [(col("Date", "year"), "Year", "year"), (col("Date", "quarter"), "Quarter", "quarter"),
               (col("Date", "month_name"), "Month", "month")] + extra_slicers
    y = KPI_Y + 30
    for i, (field, title, sync) in enumerate(slicers):
        p.slicer(f"slicer{i}", PANEL_X + 8, y, PANEL_W - 16, 56, field, title, sync)
        y += 64
    p.textbox("note", PANEL_X + 8, H - 92, PANEL_W - 16, 64,
              [[("Source: RetailDWH (SQL Server)", {"fontSize": "8pt", "color": MUTED})],
               [("Jan 2024 – Dec 2025 · net revenue, cancelled online orders excluded", {"fontSize": "8pt", "color": MUTED})]])

def kpis(p, items):
    for i, ((x, wd), (m, accent)) in enumerate(zip(cols(len(items)), items)):
        p.card(f"kpi{i}", x, KPI_Y, wd, KPI_H, m, accent=accent)

def build_pages():
    pages = []
    MONTH = col("Date", "Month")

    # 1. Overview ------------------------------------------------------------
    p = Page("overview", "Executive Overview", "Sales performance across stores and online")
    chrome(p, [(col("Product", "department_name"), "Department", "department")])
    kpis(p, [("Total Revenue", NAVY), ("Revenue YoY %", GREEN), ("Total Orders", NAVY),
             ("Avg Order Value", NAVY), ("Active Customers", NAVY), ("Online Share %", TEAL)])
    (x1, w1), (x2, w2) = [(CX, 640), (CX + 640 + GAP, CW - 640 - GAP)]
    p.chart("trend", x1, R1_Y, w1, R1_H, "lineChart", "Monthly Revenue by Channel", MONTH,
            [mea("Store Revenue"), mea("Online Revenue")], sort_by=MONTH, sort_dir="Ascending", legend=True,
            colors=[NAVY, TEAL])
    p.chart("dept", x2, R1_Y, w2, R1_H, "clusteredBarChart", "Revenue by Department",
            col("Product", "department_name"), [mea("Total Revenue")], sort_by=mea("Total Revenue"), colors=[NAVY])
    (x1, w1), (x2, w2) = cols(2)
    p.chart("topprod", x1, R2_Y, w1, R2_H, "clusteredBarChart", "Top 10 Products by Revenue",
            col("Product", "product_name"), [mea("Total Revenue")], sort_by=mea("Total Revenue"),
            filters=topn_filter("Product", "product_name", "Total Revenue"), colors=[BLUE])
    p.chart("region", x2, R2_Y, w2, R2_H, "clusteredColumnChart", "Store Revenue by Region",
            col("Store", "region"), [mea("Store Revenue")], sort_by=mea("Store Revenue"), colors=[NAVY])
    pages.append(p)

    # 2. Customers -----------------------------------------------------------
    p = Page("customers", "Customer Insights", "Who buys, where, and how much")
    chrome(p, [(col("Customer", "loyalty_level"), "Loyalty Level", "loyalty"),
               (col("Customer", "city"), "Customer City", "city")])
    kpis(p, [("Active Customers", NAVY), ("Revenue per Customer", NAVY), ("Store Customers", NAVY),
             ("Online Customers", TEAL), ("Avg Order Value", NAVY)])
    (a, aw), (b, bw), (c, cw) = cols(3)
    p.chart("loyalty", a, R1_Y, aw, R1_H, "clusteredColumnChart", "Revenue by Loyalty Level",
            col("Customer", "loyalty_level"), [mea("Total Revenue")], sort_by=mea("Total Revenue"), colors=[NAVY])
    p.chart("gender", b, R1_Y, bw, R1_H, "donutChart", "Revenue by Gender",
            col("Customer", "gender"), [mea("Total Revenue")], sort_by=mea("Total Revenue"))
    p.chart("city", c, R1_Y, cw, R1_H, "clusteredBarChart", "Active Customers by City",
            col("Customer", "city"), [mea("Active Customers")], sort_by=mea("Active Customers"), colors=[TEAL])
    p.table("topcust", CX, R2_Y, CW, R2_H, "Top 10 Customers by Revenue",
            [col("Customer", "customer_label"), col("Customer", "loyalty_level"), col("Customer", "city"),
             mea("Total Revenue"), mea("Total Orders"), mea("Avg Order Value")], mea("Total Revenue"),
            filters=topn_filter("Customer", "customer_label", "Total Revenue"))
    pages.append(p)

    # 3. Products & Promotions -----------------------------------------------
    p = Page("products", "Products & Promotions", "What sells and what promotions deliver")
    chrome(p, [(col("Product", "department_name"), "Department", "department"),
               (col("Product", "brand_name"), "Brand", "brand")])
    kpis(p, [("Total Revenue", NAVY), ("Units Sold", NAVY), ("Promo Revenue %", ORANGE), ("Discount Given", ORANGE)])
    (x1, w1), (x2, w2) = cols(2)
    p.chart("dept", x1, R1_Y, w1, R1_H, "clusteredBarChart", "Revenue by Department",
            col("Product", "department_name"), [mea("Total Revenue")], sort_by=mea("Total Revenue"), colors=[NAVY])
    p.chart("brand", x2, R1_Y, w2, R1_H, "clusteredBarChart", "Top 10 Brands by Revenue",
            col("Product", "brand_name"), [mea("Total Revenue")], sort_by=mea("Total Revenue"),
            filters=topn_filter("Product", "brand_name", "Total Revenue"), colors=[BLUE])
    p.chart("promo", x1, R2_Y, w1, R2_H, "clusteredColumnChart", "Revenue by Promotion Type",
            col("Promotion", "promo_type"), [mea("Total Revenue")], sort_by=mea("Total Revenue"), colors=[ORANGE])
    p.table("promotable", x2, R2_Y, w2, R2_H, "Promotion Performance",
            [col("Promotion", "promo_type"), mea("Total Revenue"), mea("Discount Given"), mea("Units Sold")],
            mea("Total Revenue"))
    pages.append(p)

    # 4. Online & Delivery ---------------------------------------------------
    p = Page("online", "Online Orders & Delivery", "Order flow, fulfilment and delivery speed")
    chrome(p, [(col("Delivery Provider", "provider_name"), "Delivery Provider", "provider"),
               (col("Online Sales", "payment_method"), "Payment Method", "payment")])
    kpis(p, [("Online Orders", TEAL), ("Online Revenue", TEAL), ("Delivery Rate %", GREEN),
             ("Avg Delivery Days", NAVY), ("Cancellation Rate %", RED), ("Return Rate %", RED)])
    (x1, w1), (x2, w2) = cols(2)
    p.chart("ordtrend", x1, R1_Y, w1, R1_H, "lineChart", "Online Orders by Month", MONTH,
            [mea("Online Orders")], sort_by=MONTH, sort_dir="Ascending", colors=[TEAL])
    p.chart("status", x2, R1_Y, w2, R1_H, "donutChart", "Orders by Status",
            col("Online Sales", "order_status"), [mea("All Online Orders")], sort_by=mea("All Online Orders"))
    p.chart("provider", x1, R2_Y, w1, R2_H, "clusteredBarChart", "Avg Delivery Days by Provider",
            col("Delivery Provider", "provider_name"), [mea("Avg Delivery Days")], sort_by=mea("Avg Delivery Days"),
            colors=[NAVY])
    p.chart("warehouse", x2, R2_Y, w2, R2_H, "clusteredBarChart", "Online Orders by Warehouse",
            col("Warehouse", "warehouse_name"), [mea("Online Orders")], sort_by=mea("Online Orders"), colors=[TEAL])
    pages.append(p)

    # 5. Store Performance ---------------------------------------------------
    p = Page("stores", "Store Performance", "64 stores across 4 regions")
    chrome(p, [(col("Store", "region"), "Region", "region"), (col("Store", "city"), "Store City", "storecity")])
    kpis(p, [("Store Revenue", NAVY), ("Store Transactions", NAVY), ("Avg Basket (Store)", NAVY),
             ("Store Customers", NAVY)])
    (a, aw), (b, bw) = cols(2)
    p.chart("topstores", a, R1_Y, aw, R1_H, "clusteredBarChart", "Top 10 Stores by Revenue",
            col("Store", "store_name"), [mea("Store Revenue")], sort_by=mea("Store Revenue"),
            filters=topn_filter("Store", "store_name", "Store Revenue"), colors=[NAVY])
    p.chart("storecity", b, R1_Y, bw, R1_H, "clusteredColumnChart", "Store Revenue by City",
            col("Store", "city"), [mea("Store Revenue")], sort_by=mea("Store Revenue"), colors=[BLUE])
    p.chart("storetrend", a, R2_Y, aw, R2_H, "lineChart", "Monthly Store Revenue", MONTH,
            [mea("Store Revenue")], sort_by=MONTH, sort_dir="Ascending", colors=[NAVY])
    p.table("topemp", b, R2_Y, bw, R2_H, "Top 10 Employees by Sales",
            [col("Employee", "full_name"), col("Employee", "position"), mea("Store Revenue"), mea("Store Transactions")],
            mea("Store Revenue"), filters=topn_filter("Employee", "full_name", "Store Revenue"))
    pages.append(p)
    return pages

THEME = {
    "name": "RetailInsights",
    "dataColors": [NAVY, TEAL, BLUE, ORANGE, "#8B5CF6", GREEN, RED, "#64748B"],
    "background": "#FFFFFF", "foreground": INK, "tableAccent": NAVY,
    "good": GREEN, "neutral": ORANGE, "bad": RED,
    "textClasses": {
        "callout": {"fontFace": "Segoe UI Semibold", "fontSize": 22, "color": NAVY},
        "title": {"fontFace": "Segoe UI Semibold", "fontSize": 11, "color": INK},
        "header": {"fontFace": "Segoe UI Semibold", "fontSize": 11, "color": INK},
        "label": {"fontFace": "Segoe UI", "fontSize": 9, "color": MUTED}},
    "visualStyles": {
        "page": {"*": {"background": [{"color": {"solid": {"color": PAGE_BG}}, "transparency": 0}],
                       "outspace": [{"color": {"solid": {"color": PAGE_BG}}, "transparency": 0}]}},
        "*": {"*": {"border": [{"show": True, "color": {"solid": {"color": LINE}}, "radius": 10}],
                    "dropShadow": [{"show": False}]}}},
}

def build():
    if os.path.isdir(RPT):
        shutil.rmtree(RPT)
    pages = build_pages()
    for p in pages:
        p.write()
    w(os.path.join(DEF, "pages", "pages.json"), {"$schema": f"{SCHEMA}/pagesMetadata/1.1.0/schema.json",
                                                 "pageOrder": [p.key for p in pages], "activePageName": pages[0].key})
    w(os.path.join(DEF, "version.json"), {"$schema": f"{SCHEMA}/versionMetadata/1.0.0/schema.json", "version": "2.0.0"})
    ver = {"visual": "2.8.0", "report": "3.2.0", "page": "2.3.1"}
    w(os.path.join(DEF, "report.json"), {
        "$schema": f"{SCHEMA}/report/3.3.0/schema.json",
        "themeCollection": {"baseTheme": {"name": "CY26SU04", "reportVersionAtImport": ver, "type": "SharedResources"},
                            "customTheme": {"name": "RetailInsights.json", "reportVersionAtImport": ver,
                                            "type": "RegisteredResources"}},
        "objects": {"section": [{"properties": {"verticalAlignment": s("Top")}}],
                    "outspacePane": [{"properties": {"expanded": lit("false")}}]},
        "resourcePackages": [
            {"name": "SharedResources", "type": "SharedResources",
             "items": [{"name": "CY26SU04", "path": "BaseThemes/CY26SU04.json", "type": "BaseTheme"}]},
            {"name": "RegisteredResources", "type": "RegisteredResources",
             "items": [{"name": "RetailInsights.json", "path": "RetailInsights.json", "type": "CustomTheme"}]}],
        "settings": {"useStylableVisualContainerHeader": True, "exportDataMode": "AllowSummarized",
                     "defaultDrillFilterOtherVisuals": True, "allowChangeFilterTypes": True,
                     "useEnhancedTooltips": True, "useDefaultAggregateDisplayName": True}})
    base_dir = os.path.join(RPT, "StaticResources", "SharedResources", "BaseThemes")
    os.makedirs(base_dir, exist_ok=True)
    shutil.copy(BASE_THEME_SRC, os.path.join(base_dir, "CY26SU04.json"))
    w(os.path.join(RPT, "StaticResources", "RegisteredResources", "RetailInsights.json"), THEME)
    w(os.path.join(RPT, "definition.pbir"), {"version": "4.0", "datasetReference": {"byPath": {"path": "../RetailDashboard.SemanticModel"}}})
    w(os.path.join(RPT, ".platform"), {
        "$schema": "https://developer.microsoft.com/json-schemas/fabric/gitIntegration/platformProperties/2.0.0/schema.json",
        "metadata": {"type": "Report", "displayName": "RetailDashboard"},
        "config": {"version": "2.0", "logicalId": str(uuid.uuid5(uuid.NAMESPACE_URL, "retaildwh/report"))}})
    w(os.path.join(ROOT, "RetailDashboard.pbip"), {"version": "1.0", "artifacts": [{"report": {"path": "RetailDashboard.Report"}}],
                                                   "settings": {"enableAutoRecovery": True}})
    w(os.path.join(ROOT, ".gitignore"), "**/.pbi/localSettings.json\n**/.pbi/cache.abf\n")
    print("report written:", len(pages), "pages,", sum(len(p.visuals) for p in pages), "visuals")

if __name__ == "__main__":
    build()
