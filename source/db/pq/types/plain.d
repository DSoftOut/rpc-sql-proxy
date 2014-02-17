// Written in D programming language
/**
*   PostgreSQL common types binary format.
*
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module db.pq.types.plain;

import db.pq.types.oids;
import vibe.data.json;
import std.numeric;
import util;

alias ushort RegProc;
alias ushort Oid;
alias uint Xid;
alias uint Cid;

struct PQTid
{
    uint blockId, blockNumber;
}

bool convert(PQType type)(ubyte[] val)
    if(type == PQType.Bool)
{
    assert(val.length == 1);
    return val[0] != 0;
}

string convert(PQType type)(ubyte[] val)
    if(type == PQType.ByteArray)
{
    return cast(string)val.dup;
}

char convert(PQType type)(ubyte[] val)
    if(type == PQType.Char)
{
    assert(val.length == 1);
    return cast(char)val[0];
}

string convert(PQType type)(ubyte[] val)
    if(type == PQType.Name)
{
    assert(val.length == 64);
    return cast(string)val.dup;
}

long convert(PQType type)(ubyte[] val)
    if(type == PQType.Int8)
{
    assert(val.length == 8);
    return (cast(long[])val)[0];
}

short convert(PQType type)(ubyte[] val)
    if(type == PQType.Int2)
{
    assert(val.length == 2);
    return (cast(short[])val)[0];
}

short[] convert(PQType type)(ubyte[] val)
    if(type == PQType.Int2Vector)
{
    assert(val.length % 2 == 0);
    return (cast(short[])val).dup;
}

int convert(PQType type)(ubyte[] val)
    if(type == PQType.Int4)
{
    assert(val.length == 4);
    return (cast(int[])val)[0];
}

RegProc convert(PQType type)(ubyte[] val)
    if(type == PQType.RegProc)
{
    assert(val.length == 4);
    return (cast(ushort[])val)[0];
}

string convert(PQType type)(ubyte[] val)
    if(type == PQType.Text)
{
    assert(val.length > 0);
    return fromStringz(cast(char*)val.ptr);
}

Oid convert(PQType type)(ubyte[] val)
    if(type == PQType.Oid)
{
    assert(val.length == 2);
    return (cast(ushort[])val)[0];
}

PQTid convert(PQType type)(ubyte[] val)
    if(type == PQType.Tid)
{
    assert(val.length == 8);
    PQTid res;
    res.blockId = (cast(uint[])val)[0];
    res.blockNumber = (cast(uint[])val)[1];
    return res;
}

Xid convert(PQType type)(ubyte[] val)
    if(type == PQType.Xid)
{
    assert(val.length == 4);
    return (cast(uint[])val)[0];
}

Cid convert(PQType type)(ubyte[] val)
    if(type == PQType.Cid)
{
    assert(val.length == 4);
    return (cast(uint[])val)[0];
}

Oid[] convert(PQType type)(ubyte[] val)
    if(type == PQType.OidVec)
{
    assert(val.length % 2);
    return (cast(ushort[])val).dup;
}

Json convert(PQType type)(ubyte[] val)
    if(type == PQType.Json)
{
    string payload = fromStringz(cast(char*)val.ptr);
    return parseJsonString(payload);
}

string convert(PQType type)(ubyte[] val)
    if(type == PQType.Xml)
{
    assert(val.length > 0);
    return fromStringz(cast(char*)val.ptr);
}

string convert(PQType type)(ubyte[] val)
    if(type == PQType.NodeTree)
{
    assert(val.length > 0);
    return fromStringz(cast(char*)val.ptr);
}

float convert(PQType type)(ubyte[] val)
    if(type == PQType.Float4)
{
    assert(val.length == 1);
    static assert((CustomFloat!8).sizeof == 1);
    CustomFloat!8 v = (cast(CustomFloat!8[])val)[0];
    return cast(float)v;
}

float convert(PQType type)(ubyte[] val)
    if(type == PQType.Float8)
{
    assert(val.length == 1);
    return (cast(float[])val)[0];
}

string convert(PQType type)(ubyte[] val)
    if(type == PQType.Unknown)
{
    return convert!(PQType.Text)(val);
}

long convert(PQType type)(ubyte[] val)
    if(type == PQType.Money)
{
    assert(val.length == 8);
    return (cast(long[])val)[0];
}