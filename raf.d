/* Random Access Range for File Access in D
 *
 * Author: Eduardo Pinho (enet4mikeenet AT gmail.com)
 * 
 */

/*
Copyright (c) 2015 Eduardo Pinho

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

module raf;

import std.algorithm;
import std.range;
import std.stdio;

/// Lazy random access file range. Use this.
/// Guaranteed to be a random access range.
/// No other element types but integral types were
/// tested, be warned.
public class RandomAccessFileRange(E = ubyte) {
    RandomAccessFileHandler!E h;
    ulong offset;
    ulong chunkOffset;
    ulong end;
    RandomAccessFileChunkRange!E lastChunk;

    public:
    /// create a new range
    this(string filename) {
        this(new RandomAccessFileHandler!E(filename, "rb"));
    }

    /// create a new range with a custom chunk size (default is 4KB)
    this(string filename, size_t chunkSize) {
        this(new RandomAccessFileHandler!E(filename, "rb", chunkSize));
    }

    protected:
    this(RandomAccessFileHandler!E h) {
        this(h, 0);
    }

    this(RandomAccessFileHandler!E h, ulong offset)
    in {
        assert (h !is null);
    } body {
        this.h = h;
        this.offset = offset;
        this.end = h.fileSize;
        this.lastChunk = null;
        this.seekFileChunk(offset);
    }

    this(RandomAccessFileHandler!E h, ulong offset, ulong end)
    in {
        assert (h !is null);
        assert (offset <= end);
        assert (end <= h.fileSize);
    } body {
        this.h = h;
        this.offset = offset;
        this.end = min(end, h.fileSize);
        this.lastChunk = null;
        this.seekFileChunk(offset);
    }

    public:
    @property ulong fileSize() const { return h.fileSize; }

    /// Close the underlying file. Use with caution, for
    /// it will affect all ranges pointing to this file.
    void close() {
    	this.h.close();
    }

    @property E front() {
        auto frontChunk = seekFileChunk(this.offset);
        return frontChunk[this.chunkOffset];
    }

    E moveFront() {
        auto frontChunk = seekFileChunk(this.offset);
        return frontChunk.moveAt(this.chunkOffset);
    }

    void popFront() {
        this.offset += 1;
    }

    @property bool empty() {
        return offset == end;
    }

    @property E back() {
        auto chunkRange = this.seekFileChunk(this.end-1);
        return chunkRange[this.chunkOffset];
    }

    E moveBack() {
        auto chunkRange = this.seekFileChunk(this.end-1);
        return chunkRange.moveAt(this.chunkOffset);
    }

    void popBack() {
        this.end -= 1;
    }

    @property RandomAccessFileRange!E save() {
        return new RandomAccessFileRange!E(h, offset, end);
    }

    E opIndex(size_t i) {
        auto chunkRange = this.seekFileChunk(this.offset+i);
        return chunkRange[this.chunkOffset];
    }

    E moveAt(size_t i) {
        auto chunkRange = this.seekFileChunk(this.offset+i);
        return chunkRange.moveAt(this.chunkOffset);
    }

    @property size_t length() {
        return this.end-this.offset;
    }

    alias opDollar = length;

    RandomAccessFileRange!E opSlice(size_t begin, size_t end)
    in {
        assert (begin <= end);
        assert (this.offset + end <= this.end);
    } body {
        auto effBegin = this.offset + begin;
        auto effEnd = this.offset + end;
        return new RandomAccessFileRange!E(this.h, effBegin, effEnd);
    }

    private:
    RandomAccessFileChunkRange!E seekFileChunk(ulong chunkIndex, ulong chunkOffset) {
        fetchChunk(chunkIndex);
        this.chunkOffset = chunkOffset;
        return lastChunk;
    }

    RandomAccessFileChunkRange!E seekFileChunk(ulong offset) {
        assert (offset <= fileSize);
        auto ncIndex = offset / h.chunkSize;
        auto ncOffset = offset % h.chunkSize;
        fetchChunk(ncIndex);
        this.chunkOffset = ncOffset;
        return lastChunk;
    }

    RandomAccessFileChunkRange!E fetchChunk(ulong index) {
        if (this.lastChunk is null
         || this.lastChunk.index != index) {
            this.lastChunk = new RandomAccessFileChunkRange!E(this.h, index);
        }
        return lastChunk;
    }
};

/// Handler class for caching file data chunks
private class RandomAccessFileHandler(E = ubyte)  {
    File file;
    immutable ulong size;
    size_t _chunkSize;
    E[][size_t] chunks;

    public:
    this(string filename) {
        this(filename, "rb");
    }

    this(string filename, in char[] stdioOpenmode) {
        this(filename, stdioOpenmode, 4096 / E.sizeof);
    }

    this(string filename, in char[] stdioOpenmode, size_t chunkSize) {
        this.file = File(filename, stdioOpenmode);
        this.size = file.size / E.sizeof;
        this._chunkSize = chunkSize;
    }

    ~this() {
        file.close();
    }

    /// the size of the file in elements of E (bytes if type is byte or ubyte)
    @property ulong fileSize() const { return size; }

    /// the size of the chunks in elements of E
    @property size_t chunkSize() const { return this._chunkSize; }

    void close() {
        this.file.close();
    }

    /// retrieve chunk to handler and return it
    E[] retrieveChunk(ulong i)
    out{
        assert(i in this.chunks);
        assert(this.chunks[i] !is null);
    } body {
        if (i in this.chunks) {
            return this.chunks[i];
        }

        E[] arr = new E[chunkSize];
        file.seek(i*chunkSize*E.sizeof);
        auto res = file.rawRead!E(arr);
        this.chunks[i] = res;
        return res;
    }
};

/// Lazy random access chunk range
private class RandomAccessFileChunkRange(E = ubyte) {
    RandomAccessFileHandler!E h;
    ulong ind;
    E[] chunk = null;
    size_t begin;
    size_t end;

    invariant() {
        assert(h !is null);
        assert(begin <= end);
        assert(begin <= h.fileSize);
    }

    public:
    this(RandomAccessFileHandler!E h, ulong ind)
    in {
        assert (h !is null);
        assert (ind * h.chunkSize <= h.fileSize);
    } body {
        this.h = h;
        this.ind = ind;
        this.begin = 0;
        this.end = h.chunkSize;
        this.chunk = null;
    }

    this(RandomAccessFileHandler!E h, ulong ind, E[] chunk, size_t begin, size_t end)
    in {
        assert (h !is null);
        assert (ind * h.chunkSize + begin <= h.fileSize);
        assert (begin <= end);
    } body {
        this.h = h;
        this.ind = ind;
        this.chunk = chunk;
        this.begin = begin;
        this.end = end;
    }

    // copy ctor
    this(RandomAccessFileChunkRange!E other) {
        this(other.h, other.ind, other.chunk, other.begin, other.end);
    }

    @property ulong index() const {
        return this.ind;
    }

    @property E front() {
        retrieve();
        assert (begin < end);
        return chunk[begin];
    }

    E moveFront() {
        retrieve();
        assert (begin < end);
        return move(chunk[begin]);
    }

    void popFront() {
        assert (begin < end);
        this.begin += 1;
    }

    @property bool empty() {
        return begin == end;
    }
/*
    int opApply(int delegate(E) f) {
        retrieve();
        for (auto i = begin ; i < end ; i++) {
            int r = f(chunk[i]);
            if (r != 0) return r;
        }
        return 0;

    }
*/
    int opApply(int delegate(size_t, E) f) {
        retrieve();
        for (auto i = begin ; i < end ; i++) {
            int r = f(i-begin, chunk[i]);
            if (r != 0) return r;
        }
        return 0;
    }

    @property E back() {
        retrieve();
        assert (begin < end);
        return chunk[end-1];
    }

    E moveBack() {
        retrieve();
        assert (begin < end);
        return move(chunk[end-1]);
    }

    void popBack() {
        assert (begin < end);
        end -= 1;
    }

    @property RandomAccessFileChunkRange!E save() {
        return new RandomAccessFileChunkRange!E(this);
    }

    E opIndex(size_t i) {
        retrieve();
        assert (begin+i < end);
        return chunk[begin+i];
    }

    E moveAt(size_t i) {
        retrieve();
        assert (begin+i < end);
        return move(chunk[begin+i]);
    }

    @property size_t length() const {
        return this.end-this.begin;
    }

    alias opDollar = length;

    RandomAccessFileChunkRange!E opSlice(size_t begin, size_t end) {
        assert(begin <= end);
        auto effBegin = this.begin + begin;
        auto effEnd = this.begin + end;

        return new RandomAccessFileChunkRange!E(this.h, this.ind, this.chunk, effBegin, effEnd);
    }

private:
    void retrieve()
    out {
        assert (empty || this.chunk !is null);
    } body {
        if (chunk is null && !empty) {
            this.chunk = h.retrieveChunk(this.ind);
            this.end = min(this.end, this.chunk.length);
        }
    }
};
