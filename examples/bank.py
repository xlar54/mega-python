# Classes, inheritance and exceptions
class InsufficientFunds(Exception):
    pass


class Account:
    def __init__(self, owner, balance=0):
        self.owner = owner
        self.balance = balance

    def deposit(self, amount):
        self.balance += amount
        return self

    def withdraw(self, amount):
        if amount > self.balance:
            raise InsufficientFunds(f"{self.owner} has only {self.balance}")
        self.balance -= amount
        return self

    def __repr__(self):
        return f"{type(self).__name__}({self.owner!r}, {self.balance})"


class Savings(Account):
    def __init__(self, owner, balance=0, rate=3):
        super().__init__(owner, balance)
        self.rate = rate

    def add_interest(self):
        self.balance += self.balance * self.rate // 100


accounts = [Account("Ada", 100), Savings("Grace", 500, 5)]
accounts[0].deposit(50).withdraw(30)
accounts[1].add_interest()
for acc in accounts:
    print(acc)
try:
    accounts[0].withdraw(1000)
except InsufficientFunds as e:
    print("refused:", e)
richest = max(accounts, key=lambda a: a.balance)
print("richest:", richest.owner)
