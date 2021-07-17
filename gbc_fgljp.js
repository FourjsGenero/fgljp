//gbc_fgljp js extension/add-in for fgljp
//its added after gbc.js in index.html by fgljp
'use strict';
window.fgljp = new Object;
console.log("gbc_fgljp begin");
(function() {
  var _xmlAsyncFlag=true;
  var _sessId=null;
  var _numRequest=1;
  var _cmdCount=0;
  var _source=null;
  var _useSSE=false; //use Server Side Events
  var _proto=1; //UR protocol version, ist set to 2 for GBC>=4.00
  var _procId=null;
  var _isBrowser=true;
  var _metaSeen=true;
  var urlog=function(s){};
  var mylog=function(s){};
  var tryJSONs=function(data){};
  var _debug=true;
  if (_debug) {
    urlog=function(s) {
      console.log("[UR] "+s);
      //alert(s.replace(/"/g, "'"));
    }
    mylog=function(s) {
      console.log(s);
    }
    tryJSONs=function( data ) {
      if (typeof data == "object" ) {
        return JSON.stringify(data);
      }
      return data;
    }
  }
  function checkQueryParams() {
    var usp=new URLSearchParams(window.location.search);
    var useSSE=usp.get("useSSE");
    _useSSE= (useSSE=="1") ?true:false;
    _proto=window.gbcWrapper.protocolVersion;
    _isBrowser=window.gbcWrapper.isBrowser();
    mylog("_useSSE:"+_useSSE+",_proto:"+_proto+",_isBrowser:"+_isBrowser);
  }
  checkQueryParams();
  function myalert(txt) {
    console.log("alert:"+txt);
    alert(txt);
  }
  function myassert(expr,txt) {
    if (expr===false) {
      myalert(txt);
      console.trace();
    }
  }
  function getSession() {
    var ss=window.gbc.SessionService;
    return ss.getCurrent();
  }
  function getApp() {
    var sess=getSession();
    return sess.getCurrentApplication();
  }
  function procIdShort(procId) {
    var idx=procId.indexOf(":");
    return procId.substring(idx+1);
  }
  var _xmlH = null;
  function getAJAXAnswer() {
    //mylog("getAJAXAnswer readyState:"+_xmlH.readyState+",status:"+_xmlH.status);  
    if (_xmlH == null) {
      //alert("no _xmlH  in getAJAXAnswer");
      return;
    }
    if (_xmlH.readyState != 4 ) {return;}
    if (_xmlH.status != 200) {
      mylog("AJAX status:"+_xmlH.status);
      _xmlH=null;
      return;
    }
    var responseText=_xmlH.responseText;
    if (_sessId==null) {
      _sessId=_xmlH.getResponseHeader("X-FourJs-Id");
      var headers = _xmlH.getAllResponseHeaders().toLowerCase();
      mylog("got session id:"+_sessId+",headers:"+headers);
      //_wcPath=_xmlH.getResponseHeader("X-Fourjs-Webcomponent");
      var srv=_xmlH.getResponseHeader("X-Fourjs-Server");
      mylog("srv:"+srv); 
      if (_useSSE && _source == null) {
        var url=getUrlBase() + "/ua/sse/"+encodeURIComponent(_sessId)+"?appId=0";
        addEventSource(url); 
      }
    }
    var req=_xmlH;
    _xmlH=null;
    /*
    if (req.getResponseHeader("X-FourJs-Closed")=="true") {
      mylog("X-FourJs-Closed seen");
      window.document.body.innerHTML="X-FourJs-Closed:The Application ended";
      return;
    }*/
    if (responseText.length==0) {
      if (!_useSSE) { //SSE: we come back from POST without any answer
        mylog("getAJAXAnswer:!!!!!!!!!!!!!!!!NO TEXT!!!!!!!!!!!!!!!!!!");
      }
    } else {
      if (_useSSE) {
        alert("getAJAXAnswer: unwanted responseText:"+responseText);
        return;
      }
      /* following the 'classic' GAS protocol */
      if (responseText.length>1000) {
        mylog("getAJAXAnswer:"+responseText.substring(0,800)+" > ... < "+responseText.substr(-200));
      } else {
        mylog("getAJAXAnswer:"+responseText);
      }
      try {
        if (!_metaSeen) {
          _metaSeen=true;
          myMeta(responseText);
        } else {
          emitReceive(responseText);
        }
      } catch (err) {
        mylog("error: "+err.message+",stack: "+err.stack);
        alert("error: "+err.message+",stack: "+err.stack);
      }
    }
  }
  function getUrlBase() {
    var l=window.location;
    var baseurl=l.protocol+"//"+l.host;
    return baseurl;
  }
  //computes the necessary URL when running via GAS protocol
  function getUrl() {
    var usp=new URLSearchParams(window.location.search);
    var appName=encodeURIComponent(usp.get("app"));
    var appId = (_procId !== null && _procId!=_sessId ) ? encodeURIComponent(_procId) : "0";
    var sessId = encodeURIComponent(_sessId)
    var url=getUrlBase()+
      ((_sessId!==null)?
       "/ua/sua/"+sessId+"?appId="+appId+"&pageId="+_numRequest++:
       "/ua/r/"+appName+"?ConnectorURI=&Bootstrap=done");
    mylog("url:"+url);
    return url;
  }
  //sends request via AJAX , in SSE mode the POST doesn't get a result back
  //instead the SSE events get any VM protocol data
  function sendAjax(events,what,recursive) {
    if (_xmlH!=null) {
      var req=_xmlH;
      mylog("abort _xmlH with: "+req.URL+","+req.EVENTS+","+req.WHAT);
      _xmlH.onreadystatechange = null;
      _xmlH.abort();
    }
    _xmlH = new XMLHttpRequest();
    //alert("sendAjax "+events+what);
    var req=_xmlH;
    var url=getUrl();
    req.open(what,url,_xmlAsyncFlag);
    req.URL=url;
    req.EVENTS=events;
    req.WHAT=what;
    req.setRequestHeader("Content-type","text/plain");
    req.setRequestHeader("Pragma","no-cache");
    req.setRequestHeader("Cache-Control","no-store, no-cache, must-revalidate");
    req.onreadystatechange = getAJAXAnswer;
    mylog('sendAjax:'+String(what)+" ev:"+events.substring(0,events.length-1)+" to:"+url);
    req.send(what=="POST"?events:undefined);
  }
  
  function sendPOST(events,procId) {
    if (Boolean(procId)) {
      _procId=procId;
    }
    sendAjax(events.trim()+"\n","POST");
    _procId=null;
  }
  function myMeta(meta) {
    mylog("myMeta:"+meta);
    var obj={nativeResourcePrefix: "___",
             meta:meta,
             forcedURfrontcalls:{},
             debugMode:1,
             logLevel:2};
    emitReady(obj);
  }
  function emitReady(metaobj) {
    //called by GBC
    window.gbcWrapper.URReady = function(o) {
      console.log("URREADY:"+JSON.stringify(o));
      var sess=getSession();
      sess.addServerFeatures(["ft-lock-file"]);
      var UCName=(_proto==2)? o.content.UCName : o.UCName;
      var UCVersion =(_proto==2)? o.content.UCVersion : o.UCVersion;
      var meta='meta Client{{name "GDC"} {UCName "'+UCName+'"} {version "'+UCVersion+'"} {host "browser"} {encapsulation "0"} {filetransfer "0"}}\n';
      myassert(_sessId!=null);
      console.log("meta:",meta);
      sendPOST(meta,o.procId);
    }

    //called by GBC
    window.gbcWrapper.childStart = function() {
      urlog("childStart");
    }
    window.gbcWrapper.close = function(data) {
      urlog("gbcWrapper.close:"+tryJSONs(data));
    }
    window.gbcWrapper.interrupt = function(data) {
      urlog("gbcWrapper.interrupt:"+tryJSONs(data));
    }
    window.gbcWrapper.ping = function() {
      urlog("ping");
    }
    window.gbcWrapper.processing = function(isProcessing) {
      urlog("processing: "+isProcessing);
    }
    window.gbcWrapper.showDebugger = function(data) {
      urlog("window.gbcWrapper.showDebugger:"+tryJSONs(data));
      var url = window.gbc.UrlService.currentUrl();
      url.removeQueryString("app");
      url.removeQueryString("useSSE");
      url.removeQueryString("UR_PLATFORM_TYPE");
      url.removeQueryString("UR_PLATFORM_NAME");
      url.removeQueryString("UR_PROTOCOL_TYPE");
      url.removeQueryString("UR_PROTOCOL_VERSION");
      var s=url.addQueryString("monitor", !0).toString();
      window.open(s);
    }
    window.gbcWrapper.send = function(data, options) {
      urlog("gbcWrapper.send:"+tryJSONs(data)+",options:"+tryJSONs(options));
      if (_source == null) {
        mylog("no source anymore");
        return;
      }
      var d= (_proto==2) ? data.content : data;
      var procId = (_proto==2) ? data.procId: null;
      var events="event _om "+_cmdCount+"{}{"+d+"}\n";
      _cmdCount+=1;
      sendPOST(events,procId);
    }
    window.gbcWrapper._forcedURfrontcalls= {
    "webcomponent": "*",
    "qa": ["startqa", "removestoredsettings", "getattribute", "playeventlist",
           "geterrors", "checktableishighlighted", "clicktablecell",
           "gettablecolumninfo", "gettableattributebyid","getinformation","gettablefocuscolumnrow"]
    //"qa": ["startqa", "removestoredsettings", "getattribute" ]
    };
    //for now: GBC handles all frontcalls
    window.gbcWrapper.isFrontcallURForced=function(moduleName, functionName) {
      return true;
    }
    window.gbcWrapper.frontcall = function(data, callback) {
      console.log("[gURAPI debug] frontcall(" + data + ") "+ callback);
      window._fc_callback=callback;
    };
    //not used for now
    //could be called by fgljp on another SSE channel/other tag
    window.clientfrontCallBack = function(code) {
      var fc=window._fc_callback;
      window._fc_callback=null;
      //we just pass the status here,
      //the real result is sent to the VM if GBC returns to GMI
      var error=null;
      var result="somedummyresult";
      if (code==-2 || code==-3) {
        error="failed"
        result=null;
      }
      fc({status:code ,result:result, error:error});
    }

    //signal metaobj to GBC
    window.gbcWrapper.emit("ready", metaobj);
  }
  //called by ajax/SSE
  function emitReceive(data, procId) {
    urlog("emitReceive: " + data + ",procId:" + procId);
    var d = (_proto == 2) ? { content : data, procId: procId } : data;
    window.gbcWrapper.emit("receive", d);
  }
  //SSE events
  function addEventSource(url) {
    myassert(_source===null);
    var source = new EventSource(url);
    source.addEventListener('open', function(e) {
      console.log("EventSource openened-->");
    });
    source.addEventListener('vmclose', function(e) {
      var procId = e.lastEventId;
      console.log("SSE vmclose:'"+typeof e.data+","+e.data+"',id:"+procId);
      if (e.data == "http404" ) {
        source.close();
        _source = null;
      } else {
        reAddSource(url);
      }
      try {
        emitReceive("om 10000 {{rn 0}}\n",procId);
      } catch (err) {
        mylog("error: "+err.message+",stack: "+err.stack);
      }
      /* //tried various gdc native stuff without success to close the app
      window.gbcWrapper.emit("destroyEvent", { content: { message : "destroyed" }, procId: procId} );
      try {
        window.gbcWrapper.emit("nativeAction", { name: "close" });
      } catch (err) {
        mylog("error: "+err.message+",stack: "+err.stack);
      }
      try {
        window.gbcWrapper.emit("end", {procId: procId});
      } catch (err) {
        mylog("error: "+err.message+",stack: "+err.stack);
      }
      */
    });
    source.addEventListener('meta', function(e) {
      console.log("SSE meta:'"+typeof e.data+","+e.data+"',id:"+e.lastEventId);
      var data=String(e.data);
      reAddSource(url);
      myMeta(data.trim());
    });
    source.addEventListener('message', function(e) {
      var procId = e.lastEventId;
      console.log("SSE msg data:'"+e.data+"',id:"+procId);
      var data=String(e.data);
      reAddSource(url);
      if (data && data.length>0 ) {
        if (data.charAt(0)=="[") { //multiple lines...happens in VM http mode without encaps when processing
          var arr=JSON.parse(data);
          for(var i=0;i<arr.length;i++) {
            emitReceive(arr[i],procId);
          }
        } else {
          emitReceive(data,procId);
        }
      }
    });

    source.addEventListener('error', function(e) {
       mylog("err readyState:"+e.readyState);
       if (e.readyState == EventSource.CLOSED) {
         console.log("EventSource closed");
       }
    });
    _source=source;
    mylog("added eventsource at url:"+url);
  }
  function reAddSource(url) { //needed for firefox: ignores the retry param
    //which means each SSE event causes the SSE listeners to be added again
    _source.close()
    _source=null;
    addEventSource(url);
  }
  function addGBCPatchesInt(gbc) {
    var gbcP=Object.getPrototypeOf(gbc);
    var classes=gbcP.classes;
    var VMApplicationP = classes.VMApplication.prototype;
    //wrapResourcePath should mask non conform path symbols such as \ or :
    VMApplicationP.wrapResourcePath = function(path, nativePrefix, browserPrefix) {
      // if path has a scheme, don't change it
      if (!path || /^(http[s]?|[s]?ftp|data|file|font)/i.test(path)) {
        return path;
      }
      console.log("wrapResourcePath path:"+path+",nativePrefix:"+nativePrefix+",browserPrefix:"+browserPrefix);
      //var startPath = (browserPrefix ? browserPrefix + "/" : "");
      if (nativePrefix == "webcomponents" ) {
        nativePrefix = "webcomponents/webcomponents";
      }
      var startPath = (nativePrefix ? nativePrefix + "/" : "");
      let returnPath = startPath + path;
      console.log("returnPath:"+returnPath);
      return returnPath;
    }
  }
  function addGBCPatches(gbc) {
    try {
      addGBCPatchesInt(gbc);
    } catch (err) {
      mylog("addGBCPatches:"+err.message);
    }
  }
  if (_debug) {
    fgljp.addGBCPatches=addGBCPatches;
  }
  function startWrapper() {
    mylog("gbc_fgljp startWrapper");
    addGBCPatches(window.gbc);
    sendAjax("",(_useSSE ? "POST":"GET"));
  }
  if (_isBrowser) {
    window.__gbcDefer = function (start) {//only called in "browser" mode by GBC
      mylog("__gbcDefer called in browser mode,_useSSE:"+_useSSE+",start:"+start);
      mylog("gbc ver:"+window.gbc.version);
      if (_useSSE) {
        alert("_useSSE active, not possible to be set in browser mode");
        return;
      }
      addGBCPatches(window.gbc);
      start();
    };
  } else {
    startWrapper();
  }
})();
console.log("gbc_fgljp end");
