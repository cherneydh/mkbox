#!/usr/bin/env python3
"""mkbox-update-toc.py <port> <odt-path> <pdf-path>

Internal helper for mkbox's own `mkbox -a --pdf` (see _assemble_export_pdf in the main `mkbox`
script) - not meant to be run by hand. By the time this is invoked, mkbox has already started a
headless LibreOffice instance listening for UNO connections on <port>. This connects to it, opens
<odt-path> (hidden, no UI), updates every index in the document - which is what actually computes
real page numbers for the table-of-contents field; pandoc only writes the field's *structure*, not
its page numbers - resaves the ODT with those numbers baked in, then exports <pdf-path> from that
now-updated document.

Exits non-zero (mkbox treats that as "PDF export didn't work out, the ODT is still fine") on any
failure: can't reach the LibreOffice instance, can't open the document, can't export.
"""
import os
import sys


def _prop(name, value):
    from com.sun.star.beans import PropertyValue
    p = PropertyValue()
    p.Name = name
    p.Value = value
    return p


def main():
    if len(sys.argv) != 4:
        print("usage: mkbox-update-toc.py <port> <odt-path> <pdf-path>", file=sys.stderr)
        return 1
    port = sys.argv[1]
    # LibreOffice rejects relative paths ("Unsupported URL"), and mkbox -a report.md --pdf passes one
    odt_path, pdf_path = os.path.abspath(sys.argv[2]), os.path.abspath(sys.argv[3])

    import uno

    local_ctx = uno.getComponentContext()
    resolver = local_ctx.ServiceManager.createInstanceWithContext(
        "com.sun.star.bridge.UnoUrlResolver", local_ctx)
    ctx = resolver.resolve(
        "uno:socket,host=localhost,port=%s;urp;StarOffice.ComponentContext" % port)
    smgr = ctx.ServiceManager
    desktop = smgr.createInstanceWithContext("com.sun.star.frame.Desktop", ctx)

    odt_url = uno.systemPathToFileUrl(odt_path)
    doc = desktop.loadComponentFromURL(odt_url, "_blank", 0, (_prop("Hidden", True),))
    if doc is None:
        print("mkbox-update-toc: LibreOffice couldn't open %s" % odt_path, file=sys.stderr)
        return 1

    try:
        indexes = doc.getDocumentIndexes()
        for i in range(indexes.getCount()):
            indexes.getByIndex(i).update()

        doc.store()

        pdf_url = uno.systemPathToFileUrl(pdf_path)
        doc.storeToURL(pdf_url, (_prop("FilterName", "writer_pdf_Export"),))
    finally:
        doc.close(False)

    return 0


if __name__ == "__main__":
    sys.exit(main())
