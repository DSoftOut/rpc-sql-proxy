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

import util;

import json_rpc.error;


/**
* structure describes JSON-RPC 2.0 request
*
* Example
* ------
* auto req = RpcRequest(jsonStr);
* writefln("id=%s method=%s params:%s", req.id, req.method, req.params); //these methods are read-only
* writefln("id type:", req.idType);
* ------
* 
*/
struct RpcRequest
{
	
	mixin t_field!(string, "jsonrpc");
	
	mixin t_field!(string, "method");
	
	mixin t_field!(string[], "params");
	
	/// It is necessary for some db requests.
	mixin t_field!(string, "auth");
	
	mixin t_id;
	
	this(string jsonStr)
	{
		Json json;
		try
		{
			json = parseJsonString(jsonStr);
		}
		catch(Exception ex)
		{
			throw new RpcParseError(ex.msg);
		}
		
		this(json);
	}
	
	this(in Json json)
	{
		if (json.type != Json.Type.object)
		{
			throw new RpcInvalidRequest();
		}
		
		foreach(string k, v; json)
		{
			
			//delegate
			void set(T, alias var)(bool thr = true)
			{
				Json.Type type;
				T var1;
				
				static if (is(T : string))
				{
					type = Json.Type.string;
					var1 = v.to!T;
				}
				else static if (is(T : int))
				{
					type = Json.Type.int_;
					var1 = v.to!T;
				}
				else static if (is(T == string[]))
				{
					type = Json.Type.array;
											
					var1 = new string[0];
					foreach(json; v)
					{	
						if ((json.type == Json.Type.object)||(json.type == Json.Type.object))
						{
							throw new RpcInvalidRequest("Supported only plain data in request");
						}
						var1 ~= json.to!string();
					}
				}
				else
				{
					static assert(false, "unsupported type "~T.stringof);
				}
				
				if ((v.type != type)&&(thr))
				{
					throw new RpcInvalidRequest();
				}
				
				var = var1;
				
			}
			//////////////////////////////
			
			
			if (k == "jsonrpc")
			{
				set!(string, jsonrpc);
			}
			else if (k == "method")
			{
				set!(string, method);
			}
			else if (k == "params")
			{
				set!(string[], params);
			}
			else if (k == "id")
			{				
				if (v.type == Json.Type.int_)
				{
					id = v.to!ulong;
				}
				else if (v.type == Json.Type.string)
				{
					id = v.to!string;
				}
				else if (v.type == Json.Type.null_)
				{
					id = null;
				}
				else
				{
					throw new RpcInvalidRequest("Invalid id");
				}
			}
		}
		
		if (!isValid)
		{
			throw new RpcInvalidRequest();
		}
		
		
	}
	
	void setAuth(string authStr)
	{
		this.auth = authStr;
	}
	
	bool hasAuth() @property
	{
		return f_auth;
	}
	
	private bool isComplete() @property
	{
		return f_jsonrpc && f_method;
	}
	
	private bool isJsonRpc2() @property
	{
		return jsonrpc == "2.0";
	}
	
	private bool isValid() @property
	{
		return isJsonRpc2 && isComplete;
	}
	
	version(unittest)
	{
		
		bool compare(RpcRequest s2)
		{
			if (this.id == s2.id)
			{
				if (this.method == s2.method)
				{
					if (this.jsonrpc == s2.jsonrpc)
					{
						if (this.params.length == s2.params.length)
						{
							for(int i = 0; i < s2.params.length; i++)
							{
								if( this.params[i] != s2.params[i])
								{
									return false;
								}
							}
							
							return true;
						}
					}
				}
			}
			
			return false;
		}
		
		this(string jsonrpc, string method, string[] params, string id)
		{
			this.jsonrpc = jsonrpc;
			this.method = method;
			this.params = params;
			this.id = id;
		}
		
		this(string jsonrpc, string method, string[] params, ulong id)
		{
			this.jsonrpc = jsonrpc;
			this.method = method;
			this.params = params;
			this.id = id;
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
	__gshared RpcRequest normalReq = RpcRequest("2.0", "subtract", ["42", "23"], 1);
	
	__gshared RpcRequest notificationReq = RpcRequest("2.0", "multiply", ["42", "23"], null);
	
	__gshared RpcRequest methodNotFoundReq = RpcRequest("2.0","foobar", new string[0], null);
	
	__gshared RpcRequest invalidParamsReq = RpcRequest("2.0", "subtract", ["sunday"], null);
}

unittest
{
	//Testing normal rpc request
	auto req1 = RpcRequest("2.0", "substract", ["42", "23"], "1");
	assert(!RpcRequest(example1).compare(req1), "RpcRequest test failed");
	
	//Testing RpcInvalidRequest("Supported only plain data")
	try
	{
		auto req2 = RpcRequest(example2);
		assert(false, "RpcRequest test failed");
	}
	catch(RpcInvalidRequest ex)
	{
		//nothing
	}
	
	
	//Testing rpc notification with params
	auto req3 = RpcRequest("2.0", "update", ["1", "2", "3", "4", "5"], null);
	assert(!RpcRequest(example3).compare(req3), "RpcRequest test failed");
	
	//Testing rpc notification w/o params
	auto req4 = RpcRequest("2.0", "foobar", new string[0], null);
	assert(!RpcRequest(example4).compare(req4), "RpcRequest test failed");
	
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
		assert(false, "RpcRequest test failed");
	}
	catch(RpcInvalidRequest ex)
	{
		//nothing
	}
	
	
}
