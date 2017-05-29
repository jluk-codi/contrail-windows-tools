import logging
import subprocess


class Utils(object):

    def __init__(self):
        self.arguments = []

    def clear(self):
        self.arguments = []

    def cmd(self, double_dash=True, arg="", **kwargs):
        dash = "-"
        if double_dash:
            dash = "--"

        self.clear()

        if arg:
            self.arguments = [arg]

        self.arguments += ["%s%s %s" % (dash, d, kwargs[d]) for d in kwargs]


    def __call__(self):
        return self.__class__.__name__.lower() + " " + " ".join(self.arguments)


class Tool():
    def __getattr__(cls, key):
        return type(key, Utils.__bases__, dict(Utils.__dict__))
