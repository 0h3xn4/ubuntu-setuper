"""Switch off LibreOffice's online update check in a user profile.

    python3 -I lo_update_check.py set   <registrymodifications.xcu>
    python3 -I lo_update_check.py check <registrymodifications.xcu>

'set' merges one item into the file (creating it if needed) and keeps
everything else. 'check' exits 0 if the update check is disabled, else 1.
Used by setup.sh (desktop module) and by its self-test.
"""
import sys
import xml.etree.ElementTree as ET

OOR = "http://openoffice.org/2001/registry"
XS = "http://www.w3.org/2001/XMLSchema"
XSI = "http://www.w3.org/2001/XMLSchema-instance"
PATH = "/org.openoffice.Office.Jobs/Jobs/org.openoffice.Office.Jobs:Job['UpdateCheck']/Arguments"
NAME = "AutoCheckEnabled"

ET.register_namespace("oor", OOR)
ET.register_namespace("xs", XS)
ET.register_namespace("xsi", XSI)


def find_prop(root):
    for item in root.findall("item"):
        if item.get(f"{{{OOR}}}path") == PATH:
            for prop in item.findall("prop"):
                if prop.get(f"{{{OOR}}}name") == NAME:
                    return item, prop
            return item, None
    return None, None


def is_disabled(root):
    _, prop = find_prop(root)
    if prop is None:
        return False
    value = prop.find("value")
    return value is not None and (value.text or "").strip().lower() == "false"


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("set", "check"):
        print(__doc__)
        return 2
    mode, path = sys.argv[1], sys.argv[2]
    try:
        tree = ET.parse(path)
        root = tree.getroot()
    except FileNotFoundError:
        if mode == "check":
            return 1
        root = ET.Element(f"{{{OOR}}}items")
        tree = ET.ElementTree(root)
    if mode == "check":
        return 0 if is_disabled(root) else 1
    if is_disabled(root):
        return 0
    item, prop = find_prop(root)
    if item is None:
        item = ET.SubElement(root, "item", {f"{{{OOR}}}path": PATH})
    if prop is None:
        prop = ET.SubElement(item, "prop", {f"{{{OOR}}}name": NAME, f"{{{OOR}}}op": "fuse"})
    value = prop.find("value")
    if value is None:
        value = ET.SubElement(prop, "value")
    value.text = "false"
    ET.indent(tree)
    tree.write(path, encoding="UTF-8", xml_declaration=True)
    return 0


sys.exit(main())
