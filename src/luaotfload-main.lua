-----------------------------------------------------------------------
--         FILE:  luaotfload-main.lua
--  DESCRIPTION:  Luaotfload entry point
-- REQUIREMENTS:  luatex v.0.80 or later; packages lualibs, luatexbase
--       AUTHOR:  Élie Roux, Khaled Hosny, Philipp Gesang
-----------------------------------------------------------------------
--

local osgettimeofday              = os.gettimeofday
config                            = config     or { }
luaotfload                        = luaotfload or { }
local luaotfload                  = luaotfload
luaotfload.log                    = luaotfload.log or { }
luaotfload.version                = "2.6"
luaotfload.loaders                = { }
luaotfload.min_luatex_version     = 80             --- i. e. 0.79
luaotfload.fontloader_package     = "reference"    --- default: from current Context

local authors = "\z
    Hans Hagen,\z
    Khaled Hosny,\z
    Elie Roux,\z
    Will Robertson,\z
    Philipp Gesang,\z
    Dohyun Kim,\z
    Reuben Thomas\z
"


luaotfload.module = {
    name          = "luaotfload-main",
    version       = 2.60001,
    date          = "2015/11/05",
    description   = "OpenType layout system.",
    author        = authors,
    copyright     = authors,
    license       = "GPL v2.0"
}

--[[doc--

    This file initializes the system and loads the font loader. To
    minimize potential conflicts between other packages and the code
    imported from \CONTEXT, several precautions are in order. Some of
    the functionality that the font loader expects to be present, like
    raw access to callbacks, are assumed to have been disabled by
    \identifier{luatexbase} when this file is processed. In some cases
    it is possible to trick it by putting dummies into place and
    restoring the behavior from \identifier{luatexbase} after
    initilization. Other cases such as attribute allocation require
    that we hook the functionality from \identifier{luatexbase} into
    locations where they normally wouldn’t be.

    Anyways we can import the code base without modifications, which is
    due mostly to the extra effort by Hans Hagen to make \LUATEX-Fonts
    self-contained and encapsulate it, and especially due to his
    willingness to incorporate our suggestions.

--doc]]--

local luatexbase       = luatexbase
local require          = require
local type             = type

local _error, _warning, _info, _log =
    luatexbase.provides_module(luaotfload.module)

--[[doc--

     We set the minimum version requirement for \LUATEX to v0.76,
     because the font loader requires recent features like direct
     attribute indexing and \luafunction{node.end_of_math()} that aren’t
     available in earlier versions.\footnote{%
      See Taco’s announcement of v0.76:
      \url{http://comments.gmane.org/gmane.comp.tex.luatex.user/4042}
      and this commit by Hans that introduced those features.
      \url{http://repo.or.cz/w/context.git/commitdiff/a51f6cf6ee087046a2ae5927ed4edff0a1acec1b}.
    }

--doc]]--

if tex.luatexversion < luaotfload.min_luatex_version then
    warning ("LuaTeX v%.2f is old, v%.2f or later is recommended.",
             tex.luatexversion  / 100,
             luaotfload.min_luatex_version / 100)
    warning ("using fallback fontloader -- newer functionality not available")
    luaotfload.fontloader_package = "tl2014" --- TODO fallback should be configurable too
    --- we install a fallback for older versions as a safety
end

--[[doc--

    \subsection{Module loading}
    We load the files imported from \CONTEXT with function derived this way. It
    automatically prepends a prefix to its argument, so we can refer to the
    files with their actual \CONTEXT name.

--doc]]--

local make_loader_name = function (prefix, name)
    local msg = luaotfload.log and luaotfload.log.report
             or function (...) texio.write_nl ("log", ...) end
    if not name then
        msg ("both", 0, "load",
             "Fatal error: make_loader_name (“%s”, “%s”).",
             tostring (prefix), tostring (name))
        return "dummy-name"
    end
    name = tostring (name)
    if prefix == false then
        msg ("log", 9, "load",
             "No prefix requested, passing module name “%s” unmodified.",
             name)
        return tostring (name) .. ".lua"
    end
    prefix = tostring (prefix)
    msg ("log", 9, "load",
         "Composing module name from constituents %s, %s.",
         prefix, name)
    return prefix .. "-" .. name .. ".lua"
end

local timing_info = {
    t_load = { },
    t_init = { },
}

local make_loader = function (prefix)
    return function (name)
        local t_0 = osgettimeofday ()
        local modname = make_loader_name (prefix, name)
        local data = require (modname)
        local t_end = osgettimeofday ()
        timing_info.t_load [name] = t_end - t_0
        return data
    end
end

--[[doc--
    Certain files are kept around that aren’t loaded because they are part of
    the imported fontloader. In order to keep the initialization structure
    intact we also provide a no-op version of the module loader that can be
    called in the expected places.
--doc]]--

local dummy_loader = function (name)
    luaotfload.log.report ("log", 3, "load",
                           "Skipping module “%s” on purpose.",
                           name)
end

local context_loader = function (name, path)
    luaotfload.log.report ("log", 3, "load",
                           "Loading module “%s” from Context.",
                           name)
    local t_0 = osgettimeofday ()
    local modname = make_loader_name (false, name)
    local modpath = modname
    if path then
        if lfs.isdir (path) then
            luaotfload.log.report ("log", 3, "load",
                                   "Prepending path “%s”.",
                                   path)
            modpath = file.join (path, modname)
        else
            luaotfload.log.report ("both", 0, "load",
                                   "Non-existant path “%s” specified, ignoring.",
                                   path)
        end
    end
    local ret = require (modpath)
    local t_end = osgettimeofday ()
    timing_info.t_load [name] = t_end - t_0

    if ret ~= true then
        --- require () returns “true” upon success unless the loaded file
        --- yields a non-zero exit code. This isn’t per se indicating that
        --- something isn’t right, but against HH’s coding practices. We’ll
        --- silently ignore this ever happening on lower log levels.
        luaotfload.log.report ("log", 4, "load",
                               "Module “%s” returned “%s”.", ret)
    end
    return ret
end

local install_loaders = function ()
    local loaders      = { }
    local loadmodule   = make_loader "luaotfload"
    loaders.luaotfload = loadmodule
    loaders.fontloader = make_loader "fontloader"
    loaders.context    = context_loader
    loaders.ignore     = dummy_loader
----loaders.plaintex   = make_loader "luatex" --=> for Luatex-Plain

    loaders.initialize = function (name)
        local tmp       = loadmodule (name)
        local logreport = luaotfload.log.report
        if type (tmp) == "table" then
            local init = tmp.init
            if init and type (init) == "function" then
                local t_0 = osgettimeofday ()
                if not init () then
                    logreport ("log", 0, "load",
                               "Failed to load module “%s”.", name)
                    return
                end
                local t_end = osgettimeofday ()
                local d_t = t_end - t_0
                logreport ("log", 4, "load",
                           "Module “%s” loaded in %d ms.",
                           name, d_t)
                timing_info.t_init [name] = d_t
            end
        end
    end

    return loaders
end

luaotfload.main = function ()

    luaotfload.loaders = install_loaders ()
    local loaders    = luaotfload.loaders
    local loadmodule = loaders.luaotfload
    local initialize = loaders.initialize

    local starttime = osgettimeofday ()
    local init      = loadmodule "init" --- fontloader initialization
    local store     = init.early ()     --- injects the log module too
    local logreport = luaotfload.log.report

    initialize "parsers"         --- fonts.conf and syntax
    initialize "configuration"   --- configuration options

    if not init.main (store) then
        logreport ("log", 0, "load", "Main fontloader initialization failed.")
    end

    initialize "loaders"         --- Font loading; callbacks
    initialize "database"        --- Font management.
    initialize "colors"          --- Per-font colors.

    luaotfload.resolvers = loadmodule "resolvers" --- Font lookup
    luaotfload.resolvers.init ()

    if not config.actions.reconfigure () then
        logreport ("log", 0, "load", "Post-configuration hooks failed.")
    end

    initialize "features"     --- font request and feature handling
    loadmodule "letterspace"  --- extra character kerning
    loadmodule "auxiliary"    --- additional high-level functionality

    luaotfload.aux.start_rewrite_fontname () --- to be migrated to fontspec

    logreport ("both", 0, "main",
               "initialization completed in %0.3f seconds",
               osgettimeofday() - starttime)
----inspect (timing_info)
end

-- vim:tw=79:sw=4:ts=4:et
