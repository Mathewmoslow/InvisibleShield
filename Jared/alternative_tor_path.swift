// Alternative way to set the tor executable path if it's installed via Homebrew
torProcess?.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/tor") // or /usr/local/bin/tor
