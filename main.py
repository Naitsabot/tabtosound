import tab_parser
from pprint import pprint

def main():
    tab = tab_parser.Tab(16, "4/3", 6)
    pprint(tab.read("samples/small.txt"))
    tab.print()

if __name__ == "__main__":
    main()
    