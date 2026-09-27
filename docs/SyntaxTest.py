# Python シンタックスハイライトのテスト
"""
これは複数行の
docstringです
"""


def greet(name):
    message = f"Hello, {name}"
    count = 42
    if count > 10 and name is not None:
        return message
    return None


class Greeter:
    def __init__(self):
        self.value = 'single quote string'
