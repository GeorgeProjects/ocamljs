(*
 * This file is part of ocamljs, OCaml to Javascript compiler
 * Copyright (C) 2009 Skydeck, Inc
 * Copyright (C) 2010 Jake Donham
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public
 * License along with this library; if not, write to the Free
 * Software Foundation, Inc., 59 Temple Place - Suite 330, Boston,
 * MA 02111-1307, USA
 *)

let sleep ms =
  let t, u = Lwt.task () in
  let timeout () = Lwt.wakeup u () in
  let id = Dom.window#setTimeout timeout (ms *. 1000.) in
  Lwt.on_cancel t (fun () -> Dom.window#clearTimeout id);
  t

let yield () = sleep 0.

let http_request ?(headers=[]) meth url =
  let t, u = Lwt.task () in
  let meth, body =
    match meth with
      | `Get -> "GET", None
      | `Post body -> "POST", Some body in
  let r = Dom.new_XMLHttpRequest () in
  r#open_ meth url true;
  List.iter
    (fun (k, v) -> r#setRequestHeader k v)
    headers;
  let fired = ref false in
  let onreadystatechange () =
    if r#_get_readyState = 4
    then begin
      if not !fired then Lwt.wakeup u r;
      fired := true
    end in
  r#_set_onreadystatechange onreadystatechange;
  r#send (match body with Some body -> body | _ -> Ocamljs.null ());
  Lwt.on_cancel t (fun () -> r#abort);
  t
