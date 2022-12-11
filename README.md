# music-convert.sh

This is a quick & dirty bash script to convert a directory tree of FLAC files into an (approximately) equivalent directory tree of Opus files
for playback on phones or laptops that don't have lots of space.

I say approximately equivalent because the script doesn't copy over non-audio files except for placing a single cover art file into the
directory with the transcoded files. The script attempts to find a cover art file in the directory the FLAC files are in by checking some
common filenames, and will prefer that if found. Otherwise it will extract embedded album art if it exists and place that in the directory.
Embedded album art is also preserved in the files.

Both embedded art and the separate cover art are compressed with ImageMagick to have a smaller (<100 KB) footprint.

The script executes using GNU parallel. Right now the thread count is hardcoded to 8 but I'll change that tomorrow unless I forget.

## Future plans

- Support other files than FLAC (my collection may have a handful of MP3s etc.), avoiding lossy->lossy transcodes
- Add better command line parameters.
- Turn this thing into a daemon that uses inotify to watch the collection folder for updates and transcodes new/modified files
  on the fly. (Something like this probably exists already.)
