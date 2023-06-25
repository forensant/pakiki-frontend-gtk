#!/bin/bash

sizes=(128 16 256 32 48 64)

for size in "${sizes[@]}"
do
    input_file="Logo.svg"
    output_file="Logo${size}.png"
    rsvg-convert --dpi-x 72 --dpi-y 72 -w $size -h $size $input_file -o $output_file
done
