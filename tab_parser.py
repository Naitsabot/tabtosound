class Tab(object):
    def __init__(self, divisions, timesignature, strings = 6) -> None:
        # Tablature notation
        self.symbols = ["/", "\\", "~", "h", "p", "b"]
        self.notes_sharps = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        self.notes_flat = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
        
        # Tablature
        self.tab = []
        self.tab_roots = []
        
        # Tab settings
        self.divisions = divisions
        self.timesignature = timesignature
        
        # Instrument Spesific
        self.strings = strings
        
    def read(self, file) -> None:
        # Read file
        tab = []
        with open(file, "r") as f:
            tab = f.readlines()
        
        # Remove empty lines
        for line in tab:
            if line == "\n":
                tab.remove(line)
            elif line[0] == "[":
                tab.remove(line)
        
        # Get the root notes
        for i in range(self.strings):
            self.tab_roots.append(tab[i][0])
                
        # Remove the root notes and "\n"
        for i in range(len(tab)):
            tab[i] = tab[i][2:-1]
        
        # Remove pipes
        tab = [s.replace("|", "") for s in tab]
        
        # Do that thing
        result = []
        for i in range(self.strings):
            # Get every nth item starting at index i
            group = "".join(tab[j] for j in range(i, len(tab), self.strings))
            result.append(group)                
        self.tab = result
        
        return self.tab

    def print(self) -> None:
        for i in range(len(self.tab)):
            print(self.tab_roots[i] + "|" + self.tab[i])
        
    def to_MIDI_parsable(self) -> None:
        # Listify the result
        result = [list(line) for line in result]
        
        
    