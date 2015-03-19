# raf-d
Random access range for file access in D

## What's this about?

This is a simple, one-file module containing a lazy random access range for file access. That is, unlike having a more restricted kind of range or a completely different API for file I/O, this module provides a tool to seamlessly make D-style random access ranges out of files.

## Can you explain it better?

Sure, allow me to enumerate some of the current alternatives:

 * `std.file` contains a facility function for reading the entire file into an array, which by itself makes a random access range. The downside is that the operation will transfer the entire file into memory, often undesirably. It is not uncommon to find cases where a file is selectively traversed for particular data. There is no need to waste memory and perform excess file I/O, right?

 * `std.stdio` provides a wrapper for the system's file descriptor, allowing basic file I/O operations such as `read`, `fseek` and so on. Unfortunately, this does not comply to the API of a random access range. The `byChunks` function in the same package creates an input range of chunks of data from the file. By flattening these chunks with a `joiner`, we can only have an input range of the file, which is much more restricting.

This code is a nice solution to creating a random access range from a file. Unlike the first alternative, it is a lazy range that will only read from the file when so is required (e.g. calls to `front`, `back`, `opIndex`, ...). And like in the second one, reading from the file is internally performed by chunks, thus reducing the number of read system calls. At a higher level of abstraction, this range is finite, has a length (initially the file's size), can be read multiple times and is completely sliceable. Once you are sure that all content was retrieved, the file may be closed through either one of the range slices.

## What are the current features?

This implementation provides a compliant random access range for a generic element type `E`. It has not been tested for types other than integral types, however. File reading is performed in chunks of 4KB by default.

Currently, only file reading is supported.

## Can I use this code for --?

You can do anything with the code as long as it complies to the MIT license.
