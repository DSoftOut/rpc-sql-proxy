// Written in D programming language
/**
*    Module describes connection pool to data bases. Pool handles
*    several connections to one or more sql servers. If connection
*    is lost, pool tries to reconnect over $(B reconnectTime) duration.
*    
*    Authors: NCrashed <ncrashed@gmail.com>
*/
module db.pool;

import db.connection;
import db.pq.api;
import std.range;
import core.time;

/**
*    The exception is thrown when there is no any free connection
*    for $(B freeConnTimeout) duration while trying to lock one.
*/
class ConnTimeoutException : Exception
{
    @safe pure nothrow this(string file = __FILE__, size_t line = __LINE__)
    {
        super("There is no any free connection to SQL servers!", file, line); 
    }
}

/**
*   The exception is thrown when invalid query interface is passed to
*   $(B isQueryReady) and $(B getQuery) methods.
*/
class UnknownQueryException : Exception
{
    @safe pure nothrow this(string file = __FILE__, size_t line = __LINE__)
    {
        super("There is no such query that is processing now!", file, line); 
    }
}

/**
*   The exception is thrown when something bad has happen while 
*   query passing to server or loading from server. This exception
*   has no bearing on the SQL errors.
*/
class QueryProcessingException : Exception
{
    @safe pure nothrow this(string msg, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line); 
    }
}

/**
*    Pool handles several connections to one or more SQL servers. If 
*    connection is lost, pool tries to reconnect over $(B reconnectTime) 
*    duration.
*
*    
*/
interface IConnectionPool
{
    /**
    *    Adds connection string to a SQL server with
    *    maximum connections count.
    *
    *    The pool will try to reconnect to the sql 
    *    server every $(B reconnectTime) is connection
    *    is dropped (or is down initially).
    */
    void addServer(string connString, size_t connNum);
    
    /**
    *   Synchronous blocking way to execute query.
    *   Throws: ConnTimeoutException, QueryProcessingException
    */
    InputRange!(shared IPGresult) execQuery(string command, string[] params);
    
    /**
    *   Asynchronous way to execute query. User can check
    *   query status by calling $(B isQueryReady) method.
    *   When $(B isQueryReady) method returns true, the
    *   query can be finalized by $(B getQuery) method.
    * 
    *   Returns: Specific interface to distinct the query
    *            among others.
    *   See_Also: isQueryReady, getQuery.
    *   Throws: ConnTimeoutException
    */
    shared(IQuery) postQuery(string command, string[] params);
    
    /**
    *   Returns true if query processing is finished (doesn't
    *   matter the actual reason, error or query object is invalid,
    *   or successful completion).
    *
    *   If the method returns true, then $(B getQuery) method
    *   can be called in non-blocking manner.
    *
    *   See_Also: postQuery, getQuery.
    */
    bool isQueryReady(shared IQuery query) nothrow;
    
    /**
    *   Retrieves SQL result from specified query.
    *   
    *   If previously called $(B isQueryReady) returns true,
    *   then the method is not blocking, else it falls back
    *   to $(B execQuery) behave.
    *
    *   See_Also: postQuery, isQueryReady
    *   Throws: UnknownQueryException, QueryProcessingException
    */
    InputRange!(shared IPGresult) getQuery(shared IQuery query);
    
    /**
    *    If connection to a SQL server is down,
    *    the pool tries to reestablish it every
    *    time units returned by the method. 
    */
    Duration reconnectTime() @property;
    
    /**
    *    If there is no free connection for 
    *    specified duration while trying to
    *    initialize SQL query, then the pool
    *    throws $(B ConnTimeoutException) exception.
    */
    Duration freeConnTimeout() @property;
    
    /**
    *    Returns current alive connections number.
    */
    size_t activeConnections() @property;

    /**
    *    Returns current frozen connections number.
    */
    size_t inactiveConnections() @property;
        
    /**
    *    Awaits all queries to finish and then closes each connection.
    *    Calls $(B callback) when connections are closed.
    */
    void finalize(shared void delegate() callback);
    
    /**
    *   Returns first free connection from the pool.
    *   Throws: ConnTimeoutException
    */
    protected shared(IConnection) fetchFreeConnection();
    
    protected interface IQuery {}
}
