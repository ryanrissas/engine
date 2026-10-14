"""Re-emit each failed test from a `flutter test --file-reporter json:` file as
a workflow ::error annotation, so failures are readable from the check-run API
(the raw job log is not always reachable)."""
import json, sys

tests, out = {}, []
for line in open(sys.argv[1], encoding="utf-8"):
    try:
        e = json.loads(line)
    except ValueError:
        continue
    t = e.get("type")
    if t == "testStart":
        tests[e["test"]["id"]] = e["test"]
    elif t == "error":
        test = tests.get(e.get("testID"), {})
        name = test.get("name", "?")
        url = test.get("root_url") or test.get("url") or ""
        path = url.split("/test/", 1)[-1] if "/test/" in url else "?"
        line_no = test.get("root_line") or test.get("line") or 1
        msg = (e.get("error") or "").strip().replace("\r", "")
        msg = " | ".join(l.strip() for l in msg.splitlines() if l.strip())[:900]
        out.append((f"test/{path}", line_no, name, msg))
for path, line_no, name, msg in out[:40]:
    msg = msg.replace("%", "%25").replace("\n", " ")
    name = name.replace(",", ";").replace("::", ":")[:200]
    print(f"::error file={path},line={line_no},title={name}::{msg}")
