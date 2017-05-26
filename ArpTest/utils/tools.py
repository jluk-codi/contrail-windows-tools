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

    def execute(self, prefix=""):
        if prefix:
            self.arguments = [prefix] + self.arguments
        else:
            self.arguments = [self.__class__.__name__.lower()] + self.arguments

        try:
            ret = subprocess.call(self.arguments)

        except Exception as e:
            logging.error("Error during subprocess.call on command: %s" % " ".join(self.arguments))
            raise

        return ret

    def __repr__(self):
	print self.__class__.__name__.lower() + " " + " ".join(self.arguments)


class Tool():
    def __getattr__(cls, key):
        return type(key, Utils.__bases__, dict(Utils.__dict__))
