#!/bin/bash
set -euo pipefail
shopt -s extglob

VERSION="0.5"

# Check dependencies
if ! command -v metaflac &> /dev/null; then
    echo "metaflac is not installed. Aborting."
    exit 1
fi
if ! command -v opusenc &> /dev/null; then
    echo "opusenc is not installed. Aborting."
    exit 1
fi
if ! command -v exiftool &> /dev/null; then
    echo "exiftool is not installed. Aborting."
    exit 1
fi
if ! command -v convert &> /dev/null; then
    echo "ImageMagick (convert) is not installed. Aborting."
    exit 1
fi
if ! command -v parallel &> /dev/null; then
    echo "parallel is not installed. Aborting."
    exit 1
fi

print_usage() {
    echo "Usage: $(basename $0) [-h] [-v] [-q] [-j jobs] [-y] /path/to/input/flacs /path/to/output/opuses"
}

#Default values for command line options
jobs=8
progress=true
confirm=true

while getopts ':qj:hvy' opt; do
    case "$opt" in
        q)
            progress=false
            ;;
        j)
            if [[ $OPTARG != ?(-)+([0-9]) ]]; then
                echo "jobs parameter must be an integer."
                exit 1
            fi
            jobs="$OPTARG"
            ;;

        h)
            print_usage
            echo ""
            echo "Options:"
            echo "  -h         display this help text and exit"
            echo "  -v         display version and exit"
            echo "  -q         quiet output (do not show GNU parallel progress bar)"
            echo "  -j <jobs>  number of threads to use for transcoding (default: 8)"
            echo "  -y         skip confirm prompt"
            exit 0
            ;;
        
        v)
            echo "music-convert.sh version $VERSION"
            exit 0
            ;;
        
        y)
            confirm=false
            ;;

        :)
            echo "option that expected an argument received no argument."
            exit 1
            ;;
        
        ?)
            echo -e "Invalid option."
            print_usage
            exit 1
            ;;
    esac
done

#Shift args by the number of options
shift "$(($OPTIND - 1))"

#Check params
if [[ "$#" -lt 2 ]]; then
    echo "Error: too few parameters."
    exit 1
fi
if [[ "$#" -gt 2 ]]; then
    echo "Error: too many parameters."
    exit 1
fi
export flac_dir=$(realpath "$1")
if [[ ! -e "$flac_dir" ]]; then
    echo "Input directory not found: $1"
    exit 1
fi

export opus_dir=$(realpath "$2")
export temp_dir="/tmp/musicconvert"
if [[ -e "$temp_dir" ]]; then
    echo "Temporary directory (${temp_dir}) already exists, exiting."
    exit 1
fi

if [ "$confirm" = true ]; then
    file_count=$(find "$flac_dir" -name "*.flac" | wc -l)
    echo "This will convert up to $file_count FLACs from $flac_dir into $opus_dir."
    read -p "Are you sure? (y/N) " -n 1 -r
    echo  
    if [[ ! $REPLY =~ ^[Yy]$ ]]
    then
        echo "Aborting."
        exit 1
    fi
fi

convert_file() {
    escape_regex () (
        printf %s "$1" | sed 's/[][()\.^$?*+]/\\&/g'
    )

    find_art () (
        albumartist=$(printf '%s\n' "$1" | grep "Albumartist:" | sed -n "s/^.*Albumartist:\s*\(.*\)$/\1/p" )
        albumartist=$(escape_regex "$albumartist")
        albumname=$(printf '%s\n' "$1" | grep "Album:" | sed -n "s/^.*Album:\s*\(.*\)$/\1/p")
        albumname=$(escape_regex "$albumname")
        coverart=$(find "$2" -maxdepth 1 -regextype egrep -iregex ".*/(cover|folder|$albumartist.*$albumname)\.(jpe?g|png)" -print -quit)
        printf '%s' "$coverart"
    )

    flac_file="$1"
    flac_file_noext="${flac_file%.*}"
    flac_file_dir=$(dirname "$flac_file")
    opus_file="$opus_dir/${flac_file_noext#$(printf '%q' "$flac_dir")/}.opus"
    #If the transcoded file already exists, we don't need to do anything
    if [[ -e "$opus_file" ]]; then continue; fi

    opus_file_dir=$(dirname "$opus_file")
    mkdir -p "$opus_file_dir"
    exif=$(exiftool -S "$flac_file")

    opusenc_command=(opusenc --quiet --discard-pictures --bitrate 96 --downmix-stereo)
    opusenc_files=("$flac_file" "$opus_file")

    if ! [[ $(printf '%s\n' "$exif" | grep "Picture:") ]]; then
        #If there is no embedded album art, check if there's a (cover|albumartist.?album).(jpe?g|png)
        coverart=$(find_art "$exif" "$flac_file_dir")
        if [[ -n "$coverart" ]]; then
                #Some releases include 6MB cover art, we don't need good quality so convert it to be sub 100KB
                new_cover_file="${opus_file_dir}/cover.jpg"
                #Create new file alongside output opuses if it doesn't exist already
                (
                    flock -x -w 10 200 #Lock the file so we don't race
                    if [[ ! -e "$new_cover_file" ]]; then
                        convert -define jpeg:extent=100KB -resize 500x500\> "$coverart" "$new_cover_file"
                    fi
                ) 200>"/run/user/$UID/musicconvert-$(cksum <<< $flac_file_dir | cut -f 1 -d ' ')-cover.lock"
                #Embed the file
                opusenc_command+=(--picture "${new_cover_file}")
        fi
    else
        #If there is embedded album art, make it smaller if it's large (>100 KB), and extract it to be next to the files if needed.
        coverart=$(find_art "$exif" "$flac_file_dir")
        new_cover_file="${opus_file_dir}/cover.jpg"
        if [[ -n "$coverart" ]]; then
            #We found existing coverart; let's imagemagick that to be nice and small & copy it next to the opus files
            (
                flock -x -w 10 200
                if [[ ! -e "$new_cover_file" ]]; then
                    convert -define jpeg:extent=100KB -resize 500x500\> "$coverart" "$new_cover_file"
                fi
            ) 200>"/run/user/$UID/musicconvert-$(cksum <<< $flac_file_dir | cut -f 1 -d ' ')-cover.lock"
            #no need to embed it here since there is embedded art already
        fi
        #Resize the embedded cover art if it's >100KB
        artsize=$(printf '%s\n' "$exif" | grep "PictureLength:" | sed -n "s/^.*PictureLength:\s*\(.*\)$/\1/p" )
        #We'll extract it no matter what, this way we can wipe all art from the files and embed our own one
        #(some small number of files may include multiple pictures, and we only want one really)
        extracted_art_dir=$(dirname "$temp_dir/${flac_file#$flac_dir/}")
        extracted_art_file="$extracted_art_dir/${flac_file_noext##*/}_cover.jpg"
        converted_art_file="$extracted_art_dir/${flac_file_noext##*/}_small.jpg"
        mkdir -p "$extracted_art_dir"
        metaflac --export-picture-to="$extracted_art_file" "$flac_file"

        #Convert -- this will only change the file it if it's larger than 100 KB, otherwise it's a copy
        convert -define jpeg:extent=100KB -resize 500x500\> "$extracted_art_file" "$converted_art_file"
        #Stick the converted file in the dir if there's no cover yet
        (
            flock -x -w 10 200
            if [[ ! -e "$new_cover_file" ]]; then
                cp "$converted_art_file" "$new_cover_file"
            fi
        ) 200>"/run/user/$UID/musicconvert-$(cksum <<< $flac_file_dir | cut -f 1 -d ' ')-cover.lock"
        #Finally, embed the file
        opusenc_command+=(--picture "${new_cover_file}")
    fi
    #printf '%s "%s" "%s"\n' "$opusenc_command" "$flac_file" "$opus_file"
    "${opusenc_command[@]}" "${opusenc_files[@]}"
}
export -f convert_file

#Compose parallel invocation
parallel_cmd=(parallel -0)
if [ "$progress" = true ]; then
    parallel_cmd+=(--bar)
fi
parallel_cmd+=(-j $jobs)
parallel_cmd+=(convert_file)

#Find and convert
find "$flac_dir" -name "*.flac" -print0 | "${parallel_cmd[@]}"

rm -rf "/tmp/musicconvert"
