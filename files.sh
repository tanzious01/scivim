      find . -name "*.lua" -exec bash -c 'dir=$(dirname "$(realpath "$1")"); file=$(basename "$1"); sed -i "1i-- $dir/$file" "$1"' _ {} \;
      find . -name "*.lua" -exec cat {} \; > all.lua

      # Process and combine Python files
      find . -name "*.py" -exec bash -c 'dir=$(dirname "$(realpath "$1")"); file=$(basename "$1"); sed -i "1i# $dir/$file" "$1"' _ {} \;
      find . -name "*.py" -exec cat {} \; > all.py
