package goldsrc_nav_editor

import "core:encoding/json"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "mirai:editor"
import "mirai:editor/api"
import "mirai:project"
import "mirai:std/base"
import "mirai:std/serial"
import navfile "project:plugins/goldsrc_nav/editor/navfile"

// The .nav of the bots of GoldSrc (Counter-Strike 1.6) as JSON, in the API of
// the editor (and so of its MCP server): an agent reads the areas, their
// connections, hiding spots, approaches, encounters and places, edits them and
// writes the .nav back (navfile/navfile.odin). The JSON is the one of the
// nav2json.py of the CS demo: either reads the files of the other.
//
// The engine builds its own navigation mesh from the geometry (the plugin
// navigation): this is the data of the bots of GoldSrc, for a game that ports
// them or a map that keeps them.

@(storage)
Goldsrc_Nav_Api :: struct {provider:editor.Api_Provider}

GOLDSRC_NAV_API_DEFAULT :: Goldsrc_Nav_Api{provider={register=goldsrc_nav_api_register}}

To_Json_Params :: struct {
    path:[editor.API_PATH_BYTES]u8 `mirai:"text,label=A .nav of GoldSrc, anywhere on disk; nothing is written into it"`,
    out:[editor.API_PATH_BYTES]u8 `mirai:"text,label=The JSON to write, relative to the project"`,
}

To_Nav_Params :: struct {
    path:[editor.API_PATH_BYTES]u8 `mirai:"text,label=The JSON of a .nav, relative to the project, as goldsrc_nav.to_json writes it"`,
    out:[editor.API_PATH_BYTES]u8 `mirai:"text,label=The .nav to write, relative to the project"`,
}

Summary_Params :: struct {
    path:[editor.API_PATH_BYTES]u8 `mirai:"text,label=A .nav of GoldSrc, anywhere on disk"`,
}

Nav_Result :: struct {
    version:int `mirai:"label=Version of the .nav"`,
    areas:int `mirai:"label=Areas"`,
    connections:int `mirai:"label=Connections from an area to another, each way counted"`,
    hiding_spots:int `mirai:"label=Hiding spots"`,
    approaches:int `mirai:"label=Approach entries"`,
    encounters:int `mirai:"label=Encounter paths"`,
    places:int `mirai:"label=Named places"`,
    lo:[3]f32 `mirai:"label=Lowest corner of the areas, in map units"`,
    hi:[3]f32 `mirai:"label=Highest corner of the areas, in map units"`,
}

@(private)
goldsrc_nav_api_register :: proc(s:^editor.Session) {
    editor.api_method_register(s,{name="goldsrc_nav.to_json",summary="Writes a .nav of the bots of GoldSrc (Counter-Strike 1.6) as JSON in the project: areas, connections, hiding spots, approaches, encounters and places, to read and edit.",params=To_Json_Params,params_info=type_info_of(To_Json_Params),result=Nav_Result,result_info=type_info_of(Nav_Result),run=api_to_json})
    editor.api_method_register(s,{name="goldsrc_nav.to_nav",summary="Writes the JSON of a .nav back as the .nav that Counter-Strike 1.6 reads, in the project.",params=To_Nav_Params,params_info=type_info_of(To_Nav_Params),result=Nav_Result,result_info=type_info_of(Nav_Result),run=api_to_nav})
    editor.api_method_register(s,{name="goldsrc_nav.summary",summary="Counts what a .nav of GoldSrc holds and its bounds, without writing anything.",params=Summary_Params,params_info=type_info_of(Summary_Params),result=Nav_Result,result_info=type_info_of(Nav_Result),run=api_summary})
}

// A path the API writes or reads in the project: relative to it and inside it.
@(private)
project_file :: proc(s:^editor.Session,call:^api.Call,given,field:string) -> (path:string,ok:bool) {
    if !s.has_project {api.call_fail(call,api.SERVER_ERROR,"There is no project");return}
    if given=="" || filepath.is_abs(given) || strings.contains(given,"..") {
        api.call_failf(call,api.INVALID_PARAMS,"%s %q is not a path relative to the project",field,given)
        return
    }
    return project.path(s.project_root,given,allocator=context.temp_allocator),true
}

@(private)
result_of :: proc(call:^api.Call,nav:navfile.Nav) {
    s:=navfile.summary(nav)
    out:=api.call_result(call,Nav_Result)
    out^={version=int(nav.version),areas=s.areas,connections=s.connections,hiding_spots=s.hiding_spots,approaches=s.approaches,encounters=s.encounters,places=s.places,lo=s.lo,hi=s.hi}
}

@(private)
read_nav :: proc(call:^api.Call,path:string) -> (nav:navfile.Nav,ok:bool) {
    bytes,error:=serial.file_read(path,context.temp_allocator)
    if error!=.None {api.call_failf(call,api.INVALID_PARAMS,"path %q could not be read",path);return}
    message:string
    nav,message,ok=navfile.read(bytes,context.temp_allocator)
    if !ok {api.call_failf(call,api.INVALID_PARAMS,"%s: %s",path,message)}
    return
}

@(private)
api_to_json :: proc(s:^editor.Session,call:^api.Call) {
    p:=api.call_params(call,To_Json_Params)
    out,ok:=project_file(s,call,base.text_get(p.out[:]),"out")
    if !ok {return}
    nav,read:=read_nav(call,base.text_get(p.path[:]))
    if !read {return}
    text,error:=json.marshal(nav,{pretty=true},context.temp_allocator)
    if error!=nil {api.call_failf(call,api.SERVER_ERROR,"the JSON could not be made: %v",error);return}
    os.make_directory_all(filepath.dir(out))
    if os.write_entire_file(out,text)!=nil {api.call_failf(call,api.SERVER_ERROR,"%s could not be written",out);return}
    result_of(call,nav)
}

@(private)
api_to_nav :: proc(s:^editor.Session,call:^api.Call) {
    p:=api.call_params(call,To_Nav_Params)
    source,ok:=project_file(s,call,base.text_get(p.path[:]),"path")
    if !ok {return}
    out,out_ok:=project_file(s,call,base.text_get(p.out[:]),"out")
    if !out_ok {return}
    text,error:=serial.file_read(source,context.temp_allocator)
    if error!=.None {api.call_failf(call,api.INVALID_PARAMS,"path %q could not be read",source);return}
    nav:navfile.Nav
    if e:=json.unmarshal(text,&nav,allocator=context.temp_allocator);e!=nil {api.call_failf(call,api.INVALID_PARAMS,"%s is not the JSON of a .nav: %v",source,e);return}
    os.make_directory_all(filepath.dir(out))
    if os.write_entire_file(out,navfile.write(nav,context.temp_allocator))!=nil {api.call_failf(call,api.SERVER_ERROR,"%s could not be written",out);return}
    result_of(call,nav)
}

@(private)
api_summary :: proc(s:^editor.Session,call:^api.Call) {
    p:=api.call_params(call,Summary_Params)
    nav,ok:=read_nav(call,base.text_get(p.path[:]))
    if !ok {return}
    result_of(call,nav)
}
