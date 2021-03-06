(*
 * This file is part of ocamljs, OCaml to Javascript compiler
 * Copyright (C) 2007-9 Skydeck, Inc
 * Copyright (C) 2010 Jake Donham
 * Original file (bytecomp/bytelibrarian.ml in the Objective Caml source
 * distribution) is Copyright (C) INRIA.
 *
 * This program is free software released under the QPL.
 * See LICENSE for more details.
 *
 * The Software is provided AS IS with NO WARRANTY OF ANY KIND,
 * INCLUDING THE WARRANTY OF DESIGN, MERCHANTABILITY AND 
 * FITNESS FOR A PARTICULAR PURPOSE.
 *)

open Misc
open Config
open Ocamljs_config
open Cmo_format

type error =
    File_not_found of string
  | Not_an_object_file of string

exception Error of error

(* Copy a compilation unit from a .cmjs or .cmjsa into the archive *)
let copy_compunit ic oc compunit =
  seek_in ic compunit.cu_pos;
  compunit.cu_pos <- pos_out oc;
  compunit.cu_force_link <- !Clflags.link_everything;
  copy_file_chunk ic oc compunit.cu_codesize;
  if compunit.cu_debug > 0 then begin
    seek_in ic compunit.cu_debug;
    compunit.cu_debug <- pos_out oc;
    copy_file_chunk ic oc compunit.cu_debugsize
  end

(* Add extra JS files from a library descriptor *)

let lib_ccobjs = ref []

let add_ccobjs l =
  if not !Clflags.no_auto_link then begin
    lib_ccobjs := !lib_ccobjs @ l.lib_ccobjs
  end

let copy_object_file oc name =
  let file_name =
    try
      find_in_path !load_path name
    with Not_found ->
      raise(Error(File_not_found name)) in
  let ic = open_in_bin file_name in
  try
    let buffer = String.create (String.length cmjs_magic_number) in
    really_input ic buffer 0 (String.length cmjs_magic_number);
    if buffer = cmjs_magic_number then begin
      let compunit_pos = input_binary_int ic in
      seek_in ic compunit_pos;
      let compunit = (input_value ic : compilation_unit) in
      Jslink.check_consistency file_name compunit;
      copy_compunit ic oc compunit;
      close_in ic;
      [compunit]
    end else
    if buffer = cmjsa_magic_number then begin
      let toc_pos = input_binary_int ic in
      seek_in ic toc_pos;
      let toc = (input_value ic : library) in
      List.iter (Jslink.check_consistency file_name) toc.lib_units;
      add_ccobjs toc;
      List.iter (copy_compunit ic oc) toc.lib_units;
      close_in ic;
      toc.lib_units
    end else
      raise(Error(Not_an_object_file file_name))
  with
    End_of_file -> close_in ic; raise(Error(Not_an_object_file file_name))
  | x -> close_in ic; raise x

let create_archive file_list lib_name =
  let outchan = open_out_bin lib_name in
  try
    output_string outchan cmjsa_magic_number;
    let ofs_pos_toc = pos_out outchan in
    output_binary_int outchan 0;
    let units = List.flatten(List.map (copy_object_file outchan) file_list) in
    let toc =
      { lib_units = units;
        lib_custom = false;
        lib_ccobjs = !Clflags.ccobjs @ !lib_ccobjs;
        lib_ccopts = [];
        lib_dllibs = [] } in
    let pos_toc = pos_out outchan in
    output_value outchan toc;
    seek_out outchan ofs_pos_toc;
    output_binary_int outchan pos_toc;
    close_out outchan
  with x ->
    close_out outchan;
    remove_file lib_name;
    raise x

open Format

let report_error ppf = function
  | File_not_found name ->
      fprintf ppf "Cannot find file %s" name
  | Not_an_object_file name ->
      fprintf ppf "The file %s is not a Javascript object file" name

