import std/[algorithm, strutils, sequtils, tables, math, os]


type
    Note = object
        pitch: int      # MIDI note number (0-127)
        velocity: int   # Note velocity (0-127)
        start: int      # Start time in ticks
        duration: int   # Duration in ticks

    MidiEvent = object
        time: int       # Time in ticks
        eventType: string # Type of MIDI event (e.g., "note_on", "note_off", "control_change")
        data: seq[byte] # Additional data for the event

    TabParser = object
        strings: seq[string]  # String names from top to bottom
        stringTuning: Table[string, int]  # String to MIDI note mapping
        ticksPerBeat: int # Ticks per beat
        tempo: int      # Tempo in microseconds per beat


const 
    # Standard guitar tuning (from lowest to highest string)
    # But tabs are written from highest to lowest
    STANDARD_TUNING* = {
        "e": 64,  # High E (E4)
        "B": 59,  # B3
        "G": 55,  # G3  
        "D": 50,  # D3
        "A": 45,  # A2
        "E": 40   # Low E (E2)
    }.toTable
    

    # Open C tuning (C5 variant) (from lowest to highest string) (CGCGCe)
    # But tabs are written from highest to lowest
    OPEN_C_C5_TUNING* = {
        "e": 64,  # High E (E4)
        "C": 60,  # C4
        "G": 55,  # G3  
        "C": 50,  # C3
        "G": 45,  # G2
        "C": 40   # Low C (C2)
    }.toTable



proc newTabParser(tuning: Table[string, int]): TabParser =
    result.stringTuning = tuning
    result.ticksPerBeat = 480  # Standard MIDI resolution
    result.tempo = 120         # BPM


proc parseTabLine(line: string): (string, seq[string]) =
    # Extract string name and fret positions
    let parts = line.split('|')
    if parts.len < 2:
        return ("", @[])
    
    let stringName = parts[0].strip()
    let tabContent = parts[1..^1].join("|")
    
    # Split into individual positions/beats
    var positions: seq[string] = @[]
    var currentPos = ""
    
    for c in tabContent:
        if c == '-':
            currentPos.add(c)
        elif c.isDigit:
            currentPos.add(c)
        elif c in ['r', 'h', 'p', 'b']:  # Special techniques
            currentPos.add(c)
        else:
            if currentPos.len > 0:
                positions.add(currentPos)
                currentPos = ""
    
    if currentPos.len > 0:
        positions.add(currentPos)
    
    return (stringName, positions)


proc extractFrets(position: string): seq[int] =
    # Extract fret numbers from a position string
    result = @[]
    var i = 0
    var currentNumber = ""
    
    while i < position.len:
        let c = position[i]
        if c.isDigit:
            currentNumber.add(c)
        else:
            if currentNumber.len > 0:
                try:
                    result.add(parseInt(currentNumber))
                except ValueError:
                    discard
                currentNumber = ""
        
            # Handle special techniques
            case c:
            of 'r':  # Release/return
                if i + 1 < position.len and position[i + 1].isDigit:
                    i += 1
                    currentNumber.add(position[i])
            else:
                discard
        i += 1
    
    if currentNumber.len > 0:
        try:
            result.add(parseInt(currentNumber))
        except ValueError:
            discard


proc fretToMidiNote(stringName: string, fret: int, tuning: Table[string, int]): int =
    # Convert string + fret to MIDI note number
    if stringName in tuning:
        return tuning[stringName] + fret
    return 60  # Default to middle C if string not found


proc parseTabSection(lines: seq[string], parser: TabParser): seq[Note] =
    # Parse a section of tab lines into Note objects
    result = @[]
    var stringData: seq[(string, seq[string])] = @[]
    
    # Parse each line
    for line in lines:
        if line.strip().len == 0 or not line.contains('|'):
            continue
        let (stringName, positions) = parseTabLine(line)
        if stringName.len > 0:
            stringData.add((stringName, positions))
    
    if stringData.len == 0:
        return
    
    # Find the maximum number of positions across all strings
    let maxPositions = stringData.mapIt(it[1].len).max()
    
    # Convert to notes
    for posIndex in 0..<maxPositions:
        let startTime = posIndex * (parser.ticksPerBeat div 4)  # Assume 16th note timing
        
        for (stringName, positions) in stringData:
            if posIndex < positions.len:
                let position = positions[posIndex]
                let frets = extractFrets(position)
                
                for fret in frets:
                    if fret >= 0:  # Valid fret number
                        let midiNote = fretToMidiNote(stringName, fret, parser.stringTuning)
                        let note = Note(
                            pitch: midiNote,
                            velocity: 80,
                            start: startTime,
                            duration: parser.ticksPerBeat div 4  # 16th note duration
                        )
                        result.add(note)


proc notesToMidiBytes(notes: seq[Note], ticksPerBeat: int = 480): seq[byte] =
    # Convert notes to basic MIDI file format
    result = @[]

    # MIDI Header
    result.add(@[0x4D, 0x54, 0x68, 0x64].mapIt(it.byte)) # "MThd"
    result.add(@[0x00, 0x00, 0x00, 0x06].mapIt(it.byte)) # Header length
    result.add(@[0x00, 0x00].mapIt(it.byte))                         # Format 0
    result.add(@[0x00, 0x01].mapIt(it.byte))                         # 1 track
    result.add(@[0x01, 0xE0].mapIt(it.byte))                         # Ticks per quarter note (480)
    
    # Track Header
    result.add(@[0x4D, 0x54, 0x72, 0x6B].mapIt(it.byte))  # "MTrk"
    
    var trackData: seq[byte] = @[]
    
    # Sort notes by start time
    let sortedNotes = notes.sortedByIt(it.start)
    var currentTime = 0
    
    for note in sortedNotes:
        # Delta time for note on
        let deltaTime = note.start - currentTime
        trackData.add(byte(deltaTime and 0x7F))  # Simplified delta time
        
        # Note On event
        trackData.add(@[0x90, note.pitch, note.velocity].mapIt(it.byte))
        currentTime = note.start
        
        # Delta time for note off
        trackData.add(byte(note.duration and 0x7F))
        
        # Note Off event  
        trackData.add(@[0x80, note.pitch, 0x40].mapIt(it.byte))
    
    # End of track
    trackData.add(@[0x00, 0xFF, 0x2F, 0x00].mapIt(it.byte))
    
    # Track length
    let trackLen = uint32(trackData.len)
    result.add([
        byte((trackLen shr 24) and 0xFF),
        byte((trackLen shr 16) and 0xFF), 
        byte((trackLen shr 8) and 0xFF),
        byte(trackLen and 0xFF)
    ])
    
    result.add(trackData)


proc parseTabFile*(filename: string, tuning: Table[string, int] = STANDARD_TUNING): seq[Note] =
    # Parse an entire tab file
    let parser = newTabParser(tuning)
    result = @[]
    
    try:
        let content = readFile(filename)
        let lines = content.splitLines()
        
        var currentSection: seq[string] = @[]
        
        for line in lines:
            if line.strip().len == 0:
                # Empty line - process current section
                if currentSection.len > 0:
                    let sectionNotes = parseTabSection(currentSection, parser)
                    result.add(sectionNotes)
                    currentSection = @[]
            else:
                currentSection.add(line)
        
        # Process final section
        if currentSection.len > 0:
            let sectionNotes = parseTabSection(currentSection, parser)
            result.add(sectionNotes)
            
    except IOError:
        echo "Error reading file: ", filename


proc parseTabString*(tabContent: string, tuning: Table[string, int] = STANDARD_TUNING): seq[Note] =
    # Parse tab content from a string
    let parser = newTabParser(tuning)
    result = @[]
    
    let lines = tabContent.splitLines()
    var currentSection: seq[string] = @[]
    
    for line in lines:
        if line.strip().len == 0:
            # Empty line - process current section
            if currentSection.len > 0:
                let sectionNotes = parseTabSection(currentSection, parser)
                result.add(sectionNotes)
                currentSection = @[]
        else:
            currentSection.add(line)
    
    # Process final section
    if currentSection.len > 0:
        let sectionNotes = parseTabSection(currentSection, parser)
        result.add(sectionNotes)


proc saveMidiFile*(notes: seq[Note], filename: string) =
    # Save notes as a MIDI file
    let midiData = notesToMidiBytes(notes)
    try:
        writeFile(filename, midiData.mapIt(char(it)).join(""))
        echo "MIDI file saved: ", filename
    except IOError:
        echo "Error writing MIDI file: ", filename


proc printNotes*(notes: seq[Note]) =
    # Print parsed notes for debugging
    echo "Parsed ", notes.len, " notes:"
    for i, note in notes:
        echo "Note ", i + 1, ": pitch=", note.pitch, " velocity=", note.velocity, 
                 " start=", note.start, " duration=", note.duration