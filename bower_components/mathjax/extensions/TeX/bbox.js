/*
 *  /MathJax/extensions/TeX/bbox.js
 *  
 *  Copyright (c) 2012-2013 The MathJax Consortium
 *
 *  Part of the MathJax library.
 *  See http://www.mathjax.org for details.
 * 
 *  Licensed under the Apache License, Version 2.0;
 *  you may not use this file except in compliance with the License.
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 */

MathJax.Extension["TeX/bbox"]={version:"2.3"};MathJax.Hub.Register.StartupHook("TeX Jax Ready",function(){var b=MathJax.InputJax.TeX,a=MathJax.ElementJax.mml;b.Definitions.Add({macros:{bbox:"BBox"}},null,true);b.Parse.Augment({BBox:function(e){var n=this.GetBrackets(e,""),m=this.ParseArg(e);var j=n.split(/,/),g,d,c;for(var k in j){var f=j[k].replace(/^\s+/,"").replace(/\s+$/,"");var l=f.match(/^(\.\d+|\d+(\.\d*)?)(pt|em|ex|mu|px|in|cm|mm)$/);if(l){if(g){b.Error(["MultipleBBoxProperty","%1 specified twice in %2","Padding",e])}var h=l[1]+l[3];g={height:"+"+h,depth:"+"+h,lspace:h,width:"+"+(2*l[1])+l[3]}}else{if(f.match(/^([a-z0-9]+|\#[0-9a-f]{6}|\#[0-9a-f]{3})$/i)){if(d){b.Error(["MultipleBBoxProperty","%1 specified twice in %2","Background",e])}d=f}else{if(f.match(/^[-a-z]+:/i)){if(c){b.Error(["MultipleBBoxProperty","%1 specified twice in %2","Style",e])}c=this.BBoxStyle(f)}else{if(f!==""){b.Error(["InvalidBBoxProperty","'%1' doesn't look like a color, a padding dimension, or a style",f])}}}}}if(g){m=a.mpadded(m).With(g)}if(d||c){m=a.mstyle(m).With({mathbackground:d,style:c})}this.Push(m)},BBoxStyle:function(c){return c}});MathJax.Hub.Startup.signal.Post("TeX bbox Ready")});MathJax.Ajax.loadComplete("[MathJax]/extensions/TeX/bbox.js");

