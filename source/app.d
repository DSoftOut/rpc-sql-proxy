import pgator.rpc_table;
import std.getopt;
import std.experimental.logger;
import std.typecons: Tuple;
import vibe.http.server;
import vibe.db.postgresql;

@trusted:

shared static this()
{
    sharedLog.fatalHandler = null;
}

string configFileName = "/wrong/path/to/file.json";
bool debugEnabled = false;
bool testStatements = false;

void readOpts(string[] args)
{
    try
    {
        auto helpInformation = getopt(
                args,
                "debug", &debugEnabled,
                "test", &testStatements,
                "config", &configFileName
            );
    }
    catch(Exception e)
    {
        fatal(e.msg);
    }

    if(!debugEnabled) sharedLog.logLevel = LogLevel.warning;
}

import vibe.data.json;
import vibe.data.bson;

private Bson _cfg;

Bson readConfig()
{
    import std.file;

    Bson cfg;

    try
    {
        auto text = readText(configFileName);
        cfg = Bson(parseJsonString(text));
    }
    catch(Exception e)
    {
        fatal(e.msg);
        throw e;
    }

    return cfg;
}

private struct PrepareMethodsArgs
{
    bool methodsLoadedFlag = false;
    Method[string] methods;
    size_t rpcTableLength;
    size_t failedCount;
    string tableName;
}

int main(string[] args)
{
    try
    {
        readOpts(args);
        Bson cfg = readConfig();

        auto server = cfg["sqlServer"];
        const connString = server["connString"].get!string;
        auto maxConn = to!uint(server["maxConn"].get!long);

        PrepareMethodsArgs prepArgs;

        // delegate
        void afterConnectOrReconnect(PostgresClient.Connection conn) @safe
        {
            if(prepArgs.methodsLoadedFlag)
            {
                std.experimental.logger.trace("Preparing");
                prepArgs.failedCount = prepareMethods(conn, prepArgs);

                info(prepArgs.methodsLoadedFlag, "Number of methods in the table ", prepArgs.tableName,": ", prepArgs.rpcTableLength, ", failed to prepare: ", prepArgs.rpcTableLength - prepArgs.failedCount);
            }
        }

        // connect to db
        auto client = new PostgresClient(connString, maxConn, &afterConnectOrReconnect);

        {
            auto conn = client.lockConnection();
            auto sqlPgatorTable = cfg["sqlPgatorTable"].get!string;

            // read pgator_rpc
            prepArgs.tableName = conn.escapeIdentifier(sqlPgatorTable);

            QueryParams p;
            p.sqlCommand = "SELECT * FROM "~prepArgs.tableName;
            auto answer = conn.execStatement(p, dur!"seconds"(10));

            prepArgs.rpcTableLength = answer.length;
            prepArgs.methods = readMethods(answer);
            prepArgs.methodsLoadedFlag = true;

            {
                size_t failed = prepArgs.rpcTableLength - prepArgs.methods.length;
                trace("Number of methods in the table ", prepArgs.tableName,": ", answer.length, ", failed to load into pgator: ", failed);
            }

            // prepare statements for previously used connection
            afterConnectOrReconnect(conn);
        }

        if(!testStatements)
        {
            loop(cfg, client, prepArgs.methods);
        }

        return prepArgs.failedCount ? 2 : 0;
    }
    catch(Exception e)
    {
        fatal(e.msg);

        return 1;
    }
}

void loop(in Bson cfg, PostgresClient client, in Method[string] methods)
{
    // http-server
    import vibe.core.core;

    void httpRequestHandler(scope HTTPServerRequest req, HTTPServerResponse res)
    {
        RpcRequest rpcRequest;

        try
        {
            try
            {
                rpcRequest = RpcRequest.toRpcRequest(req);
                const method = (rpcRequest.method in methods);

                if(method is null)
                    throw new LoopException(JsonRpcErrorCode.methodNotFound, HTTPStatus.badRequest, "Method "~rpcRequest.method~" not found", __FILE__, __LINE__);

                PostgresClient.Connection conn = client.lockConnection();

                if(rpcRequest.id.type != Bson.Type.undefined)
                {
                    Bson reply = Bson(["id": rpcRequest.id]);
                    reply["result"] = execPreparedStatement(conn, method, rpcRequest);
                    res.writeJsonBody(reply);
                }
                else // JSON-RPC 2.0 Notification
                {
                    execPreparedStatement(conn, method, rpcRequest);
                    res.statusCode = HTTPStatus.noContent;
                    res.statusPhrase = "Notification processed";
                    res.writeVoidBody();
                }
            }
            catch(ConnectionException e)
            {
                throw new LoopException(JsonRpcErrorCode.internalError, HTTPStatus.internalServerError, e.msg, __FILE__, __LINE__);
            }
        }
        catch(LoopException e)
        {
            Bson err = Bson.emptyObject;

            // FIXME: if id == null it is no need to reply at all, but if there was an error in detecting
            // the id in the Request object (e.g. Parse error/Invalid Request), it MUST be Null.
            err["id"] = rpcRequest.id;
            err["message"] = e.msg;
            err["code"] = e.code;

            if(e.answerException !is null)
            {
                Bson hint =    Bson(e.answerException.resultErrorField(PG_DIAG_MESSAGE_HINT));
                Bson detail =  Bson(e.answerException.resultErrorField(PG_DIAG_MESSAGE_DETAIL));
                Bson errcode = Bson(e.answerException.resultErrorField(PG_DIAG_SQLSTATE));

                err["data"] = Bson([
                    "hint": hint,
                    "detail": detail,
                    "errcode": errcode
                ]);
            }

            res.writeJsonBody(err, e.status);

            import vibe.core.log;
            logWarn(err.toString);
        }
    }

    auto settings = new HTTPServerSettings;
    settings.options |= HTTPServerOption.parseJsonBody;
    settings.bindAddresses = cfg["listenAddresses"].deserializeBson!(string[]);
    settings.port = to!ushort(cfg["listenPort"].get!long);

    auto listenHandler = listenHTTP(settings, &httpRequestHandler);

    runEventLoop();
}

private struct TransactionQueryParams
{
    QueryParams queryParams;
    AuthorizationCredentials auth;

    alias queryParams this;
}

private immutable(Answer) transaction(PostgresClient.Connection conn, in Method* method, in TransactionQueryParams qp)
{
    if(method.readOnlyFlag) // BEGIN READ ONLY
    {
        QueryParams q;
        q.preparedStatementName = beginPreparedName;
        conn.execPreparedStatement(q); // FIXME: timeout check
    }

    scope(exit)
    if(method.readOnlyFlag) // COMMIT
    {
        QueryParams q;
        q.preparedStatementName = commitPreparedName;
        auto a = conn.execPreparedStatement(q); // FIXME: timeout check
    }

    return conn.execPreparedStatement(qp); // FIXME: timeout check
}

private Bson execPreparedStatement(
    PostgresClient.Connection conn,
    in Method* method,
    in RpcRequest rpcRequest
)
{
    TransactionQueryParams qp;
    qp.preparedStatementName = rpcRequest.method;

    {
        if(rpcRequest.positionParams.length == 0) // named parameters
            qp.argsFromArray = named2positionalParameters(method, rpcRequest.namedParams);
        else // positional parameters
        {
            if(rpcRequest.positionParams.length != method.argsNames.length)
                throw new LoopException(JsonRpcErrorCode.invalidParams, HTTPStatus.badRequest, "Parameters number mismatch", __FILE__, __LINE__);

            qp.argsFromArray = rpcRequest.positionParams;
        }
    }

    try
    {
        immutable answer = conn.transaction(method, qp);

        Bson getValue(size_t rowNum, size_t colNum)
        {
            string columnName = answer.columnName(colNum);

            try
            {
                return answer[rowNum][colNum].toBson;
            }
            catch(AnswerConvException e)
            {
                e.msg = "Column "~columnName~" (row "~rowNum.to!string~"): "~e.msg;
                throw e;
            }
        }

        if(method.oneCellFlag)
        {
            if(answer.length != 1 || answer.columnCount != 1)
                throw new LoopException(JsonRpcErrorCode.internalError, HTTPStatus.internalServerError, "One cell flag constraint failed", __FILE__, __LINE__);

            return getValue(0, 0);
        }

        if(method.oneRowFlag)
        {
            if(answer.length != 1)
                throw new LoopException(JsonRpcErrorCode.internalError, HTTPStatus.internalServerError, "One row flag constraint failed", __FILE__, __LINE__);

            Bson ret = Bson.emptyObject;

            foreach(colNum; 0 .. answer.columnCount)
                ret[answer.columnName(colNum)] = getValue(0, colNum);

            return ret;
        }

        if(!method.rotateFlag)
        {
            Bson ret = Bson.emptyObject;

            foreach(colNum; 0 .. answer.columnCount)
            {
                Bson[] col = new Bson[answer.length];

                foreach(rowNum; 0 .. answer.length)
                    col[rowNum] = getValue(rowNum, colNum);

                ret[answer.columnName(colNum)] = col;
            }

            return ret;
        }
        else
        {
            Bson[] ret = new Bson[answer.length];

            foreach(rowNum; 0 .. answer.length)
            {
                Bson row = Bson.emptyObject;

                foreach(colNum; 0 .. answer.columnCount)
                    row[answer.columnName(colNum)] = getValue(rowNum, colNum);

                ret[rowNum] = row;
            }

            return Bson(ret);
        }
    }
    catch(AnswerCreationException e)
    {
        throw new LoopException(JsonRpcErrorCode.internalError, HTTPStatus.internalServerError, e.msg, __FILE__, __LINE__, e);
    }
}

string[] named2positionalParameters(in Method* method, in string[string] namedParams) pure
{
    string[] ret = new string[method.argsNames.length];

    foreach(i, argName; method.argsNames)
    {
        if(argName in namedParams)
            ret[i] = namedParams[argName];
        else
            throw new LoopException(JsonRpcErrorCode.invalidParams, HTTPStatus.badRequest, "Missing required parameter "~argName, __FILE__, __LINE__);
    }

    return ret;
}

private struct AuthorizationCredentials
{
    bool authVariablesSet = false;
    string user;
    string password;
}

struct RpcRequest
{
    Bson id;
    string method;
    string[string] namedParams = null;
    string[] positionParams = null;
    AuthorizationCredentials auth;

    invariant()
    {
        assert(namedParams is null || positionParams is null);
    }

    static RpcRequest toRpcRequest(scope HTTPServerRequest req)
    {
        if(req.contentType != "application/json")
            throw new LoopException(JsonRpcErrorCode.invalidRequest, HTTPStatus.unsupportedMediaType, "Supported only application/json content type", __FILE__, __LINE__);

        Json j = req.json;

        if(j["jsonrpc"] != "2.0")
            throw new LoopException(JsonRpcErrorCode.invalidRequest, HTTPStatus.badRequest, "Protocol version should be \"2.0\"", __FILE__, __LINE__);

        RpcRequest r;

        r.id = j["id"];
        r.method = j["method"].get!string;

        Json params = j["params"];

        switch(params.type)
        {
            case Json.Type.undefined: // params omitted
                break;

            case Json.Type.object:
                foreach(string key, value; params)
                {
                    if(value.type == Json.Type.object || value.type == Json.Type.array)
                        throw new LoopException(JsonRpcErrorCode.invalidParams, HTTPStatus.badRequest, "Unexpected named parameter type", __FILE__, __LINE__);

                    r.namedParams[key] = value.to!string;
                }
                break;

            case Json.Type.array:
                foreach(value; params)
                {
                    if(value.type == Json.Type.object || value.type == Json.Type.array)
                        throw new LoopException(JsonRpcErrorCode.invalidParams, HTTPStatus.badRequest, "Unexpected positional parameter type", __FILE__, __LINE__);

                    r.positionParams ~= value.to!string;
                }
                break;

            default:
                throw new LoopException(JsonRpcErrorCode.invalidParams, HTTPStatus.badRequest, "Unexpected params type", __FILE__, __LINE__);
        }

        // pick out name and password from the request
        {
            import std.string;
            import std.base64;

            // Copypaste from vibe.d code, see https://github.com/rejectedsoftware/vibe.d/issues/1449

            auto pauth = "Authorization" in req.headers;
            if( pauth && (*pauth).startsWith("Basic ") ){
                string user_pw = cast(string)Base64.decode((*pauth)[6 .. $]);

                auto idx = user_pw.indexOf(":");
                enforceBadRequest(idx >= 0, "Invalid auth string format!");

                r.auth.authVariablesSet = true;
                r.auth.user = user_pw[0 .. idx];
                r.auth.password = user_pw[idx+1 .. $];
            }
        }

        return r;
    }
}

enum JsonRpcErrorCode : short
{
    /// Invalid JSON was received by the server.
    /// An error occurred on the server while parsing the JSON text
    parseError = -32700,

    /// The JSON sent is not a valid Request object.
    invalidRequest = -32600,

    /// Method not found
    methodNotFound = -32601,

    /// Invalid params
    invalidParams = -32602,

    /// Internal error
    internalError = -32603,
}

class LoopException : Exception
{
    const JsonRpcErrorCode code;
    const HTTPStatus status;
    const AnswerCreationException answerException;

    this(JsonRpcErrorCode code, HTTPStatus status, string msg, string file, size_t line, AnswerCreationException ae = null) pure
    {
        this.code = code;
        this.status = status;
        this.answerException = ae;

        super(msg, file, line);
    }
}

immutable string beginPreparedName = "#B#";
immutable string commitPreparedName = "#C#";

/// returns number of successfully prepared methods
private size_t prepareMethods(PostgresClient.Connection conn, ref PrepareMethodsArgs args)
{
    {
        trace("try to prepare methods BEGIN READ ONLY and COMMIT");

        Method b;
        b.name = beginPreparedName;
        b.statement = "BEGIN READ ONLY";

        Method c;
        c.name = commitPreparedName;
        c.statement = "COMMIT";

        conn.prepareMethod(b);
        conn.prepareMethod(c);

        trace("BEGIN READ ONLY and COMMIT prepared");
    }

    size_t count = 0;

    foreach(const m; args.methods.byValue)
    {
        trace("try to prepare method ", m.name);

        try
        {
            conn.prepareMethod(m);

            trace("method ", m.name, " prepared");
            count++;
        }
        catch(ConnectionException e)
        {
            throw e;
        }
        catch(Exception e)
        {
            warning(e.msg, ", skipping preparing of method ", m.name);
        }
    }

    return count;
}

private void prepareMethod(PostgresClient.Connection conn, in Method method)
{
    conn.prepareStatement(method.name, method.statement, method.argsNames.length);
}
