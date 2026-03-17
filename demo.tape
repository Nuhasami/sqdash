Output demo.gif

Set Shell zsh
Set Width 1200
Set Height 700
Set FontSize 15
Set Padding 10
Set TypingSpeed 80ms

# Launch sqdash
Hide
Type "cd /Users/nuha/Lab/sqd && bundle exec ruby exe/sqdash"
Enter
Sleep 3s
Show

# Navigate the job list
Down
Sleep 400ms
Down
Sleep 400ms
Down
Sleep 400ms

# Open job detail view
Enter
Sleep 2s

# Go back
Escape
Sleep 1s

# Search for a job class
Type "/"
Sleep 500ms
Type "Export"
Sleep 1s
Tab
Sleep 800ms
Enter
Sleep 1.5s

# Clear filter
Escape
Sleep 1s

# Switch to failed view
Type ":"
Sleep 500ms
Type "view failed"
Enter
Sleep 2s

# View a failed job's error
Enter
Sleep 2s

# Go back
Escape
Sleep 1s

# Sort oldest first
Type ":"
Sleep 500ms
Type "sort created asc"
Enter
Sleep 1.5s

# Switch back to all
Type ":"
Sleep 500ms
Type "view all"
Enter
Sleep 1.5s

# Quit
Type "q"
Sleep 500ms
