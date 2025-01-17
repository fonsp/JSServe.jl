function update_route!(server, (route, app))
    old = route!(server, route => app)
    if old isa App && !isnothing(old.session[]) && isready(old.session[])
        try
            JSServe.evaljs(old.session[], js"window.location.reload()")
        catch e
            @warn "Failed to reload route $(route)" exception = e
        end
    end
end

const REVISE_LOOP = Base.RefValue(Base.RefValue(true))
const REVISE_SERVER = Base.RefValue{Union{Nothing, Server}}(nothing)

function interactive_server(f, paths, modules=[]; url="127.0.0.1", port=8081, all=true)
    if isnothing(REVISE_SERVER[])
        server = Server(url, port)
        REVISE_SERVER[] = server
    else
        server = REVISE_SERVER[]
    end
    if server.url != url && server.port != port
        close(server)
        server.url = url
        server.port = port
        HTTPServer.start(server)
    end
    if isdefined(Main, :Revise)
        Revise = Main.Revise
        # important to make `index = App(....)` work
        @eval Main __revise_mode__ = :evalassign
        returned_routes = nothing
        function update_routes()
            routes = Base.invokelatest(f)
            for (route, app) in routes.routes
                update_route!(server, (route, app))
            end
            # Update routes returned to the user, so they're up do date!
            if !isnothing(returned_routes)
                # TODO, could this be called from another task and needs a lock?
                empty!(returned_routes.routes)
                merge!(returned_routes.routes, routes.routes)
            end
            return routes
        end

        returned_routes = update_routes()
        Revise.add_callback(update_routes, paths, modules; all=true, key="jsserver-revise")

        REVISE_LOOP[][] = false # stop any old loop
        run = Base.RefValue(true) # get us a new loop variable
        REVISE_LOOP[] = run
        task = @async begin
            while run[]
                wait(Revise.revision_event)
                Revise.revise()
            end
            @info("quitting revise loop")
        end
        errormonitor(task)
        route_dict = returned_routes.routes
        user_routes = keys(route_dict)
        server_routes = Set(first.(server.routes.table))
        if !Base.all(r -> r in server_routes, user_routes)
            # Sanity check, that all routes have been added to server. Not sure how this could fail, but better to check it!
            @warn "Not all routes in server. Required routes: $(user_routes). Routes in server: $(server_routes)"
        end
        startpage = haskey(route_dict, "/") ? "/" : first(route_dict)[1]
        HTTPServer.openurl(online_url(server, startpage))
        return returned_routes, task, server
    else
        error("Please load Revise into Main scope")
    end
end
