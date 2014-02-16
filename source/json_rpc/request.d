// Written in D programming language
/**
* JSON-RPC 2.0 Protocol<br>
* 
* $(B This module contain JSON-RPC 2.0 request)
*
* See_Also:
*    $(LINK http://www.jsonrpc.org/specification)
*
* Authors: Zaramzan <shamyan.roman@gmail.com>
*
*/

module json_rpc.request;

import std.exception;

import vibe.data.json;
//import vibe.data.serialization;

import util;

import json_rpc.error;


/**
* structure describes JSON-RPC 2.0 request
*
* Example
* ------
* auto req = RpcRequest(json);
* writefln("id=%s method=%s params:%s", req.id, req.method, req.params);
* ------
* 
*/

struct RpcRequest
{	
	@required
	string jsonrpc;
	
	@required
	string method;
	
	@possible
	string[] params = null;
	
	@possible
	Json id = Json(null);
	
	string auth = null;
	
	this(Json json)
	{
		try
		{
			this = deserializeFromJson!RpcRequest(json);
		}
		catch (RequiredFieldException ex)
		{
			throw new RpcInvalidRequest(ex.msg);
		}
		catch (RequiredJsonObject ex)
		{
			throw new RpcInvalidRequest(ex.msg);
		}
		catch(Exception ex)
		{
			throw new RpcInternalError(ex.msg);
		}
	}
	
	this(string jsonStr)
	{
		Json json;
		try
		{
			json = parseJsonString(jsonStr);
		}
		catch(Exception ex)
		{
			throw new RpcParseError();
		}
		
		this = this(json);
	}
	
	version (unittest)
	{
		this(string jsonrpc, string method, string[] params, Json id)
		{
			this.jsonrpc = jsonrpc;
			
			this.method = method;
			
			this.params = params;
			
			this.id = id;
		}
		
		this(string jsonrpc, string method, string[] params)
		{
			this.jsonrpc = jsonrpc;
			
			this.method = method;
			
			this.params = params;
		}
		
		bool eq(RpcRequest s2)
		{
			if (this.id == s2.id)
			{	
				if (this.method == s2.method)
				{
					if (this.jsonrpc == s2.jsonrpc)
					{
						
							if (this.params.length == s2.params.length)
							{
								foreach(int i, string vl; s2.params)
								{
									if (this.params[i] != s2.params[i])
										return false;
								}
								
								return true;
							}
						
					}
				}
			}
			return false;
		}
	}
}


version(unittest)
{
	// For local tests
	enum example1 = 
		"{\"jsonrpc\": \"2.0\", \"method\": \"subtract\", \"params\": [42, 23], \"id\": 1}";
		
	enum example2 = 
		"{\"jsonrpc\": \"2.0\", \"method\": \"subtract\", \"params\": {\"subtrahend\": 23, \"minuend\": 42}, \"id\": 3}";
		
	enum example3 = 
		"{\"jsonrpc\": \"2.0\", \"method\": \"update\", \"params\": [1,2,3,4,5]}";
	
	enum example4 = 
		"{\"jsonrpc\": \"2.0\", \"method\": \"foobar\"}";
		
	enum example5 =
		"{\"jsonrpc\": \"2.0\", \"method\": \"foobar, \"params\": \"bar\", \"baz]";
		
	enum example6 = 
		"[]";
		
	enum example7 = 
		"{\"jsonrpc\": \"2.0\", \"method\": \"divide\", \"params\": [42, 23], \"id\": 1}";
		
	enum example8 = 
		"{\"jsonrpc\": \"2.0\", \"method\": \"mult\", \"params\": [33,22]}";
		
	//For global tests
	__gshared RpcRequest normalReq = RpcRequest("2.0", "subtract", ["42", "23"]);
	
	__gshared RpcRequest notificationReq = RpcRequest("2.0", "multiply", ["42", "23"]);
	
	__gshared RpcRequest methodNotFoundReq = RpcRequest("2.0","foobar", null);
	
	__gshared RpcRequest invalidParamsReq = RpcRequest("2.0", "subtract", ["sunday"]);
}

unittest
{
	import std.stdio;
	//Testing normal rpc request
	auto req1 = RpcRequest("2.0", "substract", ["42", "23"], Json(1));
	//std.stdio.writeln(req1);
	assert(!RpcRequest(example1).eq(req1), "RpcRequest test failed");
	
	//Testing RpcInvalidRequest("Supported only plain data")
	auto req2 = RpcRequest(example2);
	//std.stdio.writeln(req2);
	assert(req2.params is null, "RpcRequest test failed");
	
	
	//Testing rpc notification with params
	auto req3 = RpcRequest("2.0", "update", ["1", "2", "3", "4", "5"], Json(null));
	//std.stdio.writeln(req3);
	assert(RpcRequest(example3).eq(req3), "RpcRequest test failed");
	
	//Testing rpc notification w/o params
	auto req4 = RpcRequest("2.0", "foobar", null, Json(null));
	//writeln(req4);
	assert(RpcRequest(example4).eq(req4), "RpcRequest test failed");
	
	//Testing invalid json
	try
	{
		auto req5 = RpcRequest(example5);
		assert(false, "RpcRequest test failed");
	}
	catch(RpcParseError ex)
	{
		//nothiing
	}
	
	//Testing empty json array
	try
	{
		auto req6 = RpcRequest(example6);
		//std.stdio.writeln(req6);
		assert(false, "RpcRequest test failed");
	}
	catch(RpcInvalidRequest ex)
	{
		//nothing
	}
	
	
}
