# music-convert.sh

This is a quick & dirty bash script to convert a directory tree of FLAC files into an (approximately) equivalent directory tree of Opus files
for playback on phones or laptops that don't have lots of space.

I say approximately equivalent because the script doesn't copy over non-audio files except for placing a single cover art file into the
directory with the transcoded files. The script attempts to find a cover art file in the directory the FLAC files are in by checking some
common filenames, and will prefer that if found. Otherwise it will extract embedded album art if it exists and place that in the directory.
Embedded album art is also preserved in the files.

Both embedded art and the separate cover art are compressed with ImageMagick to have a smaller (<100 KB) footprint.

The script performs the transcode using [GNU parallel](https://www.gnu.org/software/parallel/).

Opusenc applies per-track replaygain as it encodes, but you will probably want to use [r128gain](https://github.com/desbma/r128gain)
to add album gain to the converted files once you're done.

## Dependencies

- **metaflac** (Fedora package: `flac`)
- **opusenc** (Fedora package: `opus-tools`)
- **exiftool** (Fedora package: `perl-Image-ExifTool`)
- **convert** from ImageMagick (Fedora package: `ImageMagick`)
- **parallel** (Fedora package: `parallel`)

## Usage

`./media-convert.sh /path/to/input/flacs /path/to/output/opuses`

For command line options, see `./media-convert.sh -h`.

## Future plans

- Support other files than FLAC (my collection may have a handful of MP3s etc.), avoiding lossy->lossy transcodes
  - Easiest way to do this would be to use ffmpeg, but ffmpeg is currently very deficient when it comes to embedding album art into Opus files.
  - Workaround would probably be something ugly like decoding the input file into a WAV using ffmpeg, then encoding that using opusenc.
    Not very nice and would likely be slow.
- Turn this thing into a daemon that uses inotify to watch the collection folder for updates and transcodes new/modified files
  on the fly. (Something like this probably exists already.)
