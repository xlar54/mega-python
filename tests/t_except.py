# exceptions
def safe_div(a, b):
    try:
        return a // b
    except ZeroDivisionError:
        return None


print(safe_div(10, 2), safe_div(1, 0))
try:
    [1, 2][5]
except IndexError as e:
    print("IndexError:", e)
try:
    int("abc")
except ValueError:
    print("ValueError from int")
try:
    undefined_name
except NameError as e:
    print("NameError:", e)
try:
    1 + "a"
except TypeError:
    print("TypeError")
try:
    x = 1
except Exception:
    print("not here")
else:
    print("else runs", x)
try:
    raise ValueError("custom message")
except (TypeError, ValueError) as e:
    print("caught", e, e.args)


class MyError(Exception):
    pass


class DetailError(Exception):
    def __init__(self, code):
        super().__init__("code " + str(code))
        self.code = code


try:
    raise MyError("mine")
except MyError as e:
    print("MyError", e)
try:
    raise DetailError(42)
except Exception as e:
    print("detail", e, e.code, isinstance(e, DetailError))
try:
    try:
        raise KeyError("inner")
    except KeyError:
        print("inner caught")
        raise
except KeyError as e:
    print("re-raised", e)
log = []
try:
    log.append("try")
    raise RuntimeError("x")
except RuntimeError:
    log.append("except")
finally:
    log.append("finally")
print(log)
try:
    log2 = []
    try:
        log2.append(1)
    finally:
        log2.append(2)
    print(log2)
except Exception:
    print("no")


def nested(n):
    if n == 0:
        raise ValueError("bottom")
    return nested(n - 1)


try:
    nested(10)
except ValueError as e:
    print("from deep:", e)
for v in [1, 0, "s", 4]:
    try:
        print(10 // v)
    except ZeroDivisionError:
        print("div by zero")
    except TypeError:
        print("bad type")
try:
    assert 1 == 2, "assertion text"
except AssertionError as e:
    print("AssertionError", e)
try:
    raise StopIteration
except StopIteration:
    print("StopIteration")
print(repr(ValueError("v")), str(KeyError("k")))
