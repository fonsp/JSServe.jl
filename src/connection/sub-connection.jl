

function SubConnection(parent::Session)
    return SubConnection(parent.connection, false)
end

function Base.write(connection::SubConnection, binary)
    write(connection.connection, binary)
end

Base.isopen(connection::SubConnection) = connection.isopen
Base.close(connection::SubConnection) = (connection.isopen = false)

function setup_connect(session::Session{SubConnection})
    return js""" """
end
