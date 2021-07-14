//uses a simple input field in the webco and an image
//the image is using the fetch API to verify we actually get resources
var input=document.getElementById("theinput");
var img=document.getElementById("theimg");

function OnKeyDown(ev) {
   mylog("OnKeyDown keycode:"+ev.keyCode);
   if(ev.keyCode === 9) {
     ev.preventDefault();
   }
}
document.onkeydown = OnKeyDown;

input.disabled=true;

function mylog(s) {
  console.log(s);
}

input.onfocus=function() {
  mylog("onfocus");
  gICAPI.SetFocus();
}

onICHostReady =function(version) { 
  gICAPI.onFocus=function(focusIn) {
    mylog("gICAPI.onFocus:"+focusIn);
    if (focusIn) {
      input.focus();
    } else if (document.activeElement==input) {
      input.blur();
    }
  }
                                
  gICAPI.onData=function(data) {
    var o=JSON.parse(data)
    mylog("gICAPI.onData:"+data);
    input.value=o.value;
    //fetchURL(o.src);
    imgLoad(o.src);
    //img.src=o.src;
  }

  gICAPI.onProperty=function(p) { 
    mylog("gICAPI.onProperty:"+p);
    var props = eval('(' + p + ')');
    if (props.active!==undefined) {
      input.disabled=props.active=="1"?false:true;
      if (input.disabled) {
        input.blur();
      }
    }
  }
}

function getData() {
  return input.value;
}

function getImgSrc() {
  return String(img.src);
}

function blob2Base64(blob) {
  var fread = new FileReader();
  fread.onerror = function() {
    sendError("File reader failed");
  }
  fread.onload = function() {
    img.src=fread.result;
    console.log("src:"+img.src);
    gICAPI.Action("gotimage");
  };
  fread.readAsDataURL(blob);
}

function imgLoad(url) {
  var req = new XMLHttpRequest();
  req.open('GET', url);
  req.responseType = 'blob';
  req.onload = function() {
    if (req.status === 200) {
      blob2Base64(req.response);
      //the following works too but misses the base64 data
      //var imageURL = window.URL.createObjectURL(req.response);
      //img.src = imageURL;
      //gICAPI.Action ("gotimage");
    } else {
      sendError("Image didn\'t load successfully; code:"+req.status+",error :" + req.statusText);
    }
  };
  req.onerror = function() {
    sendError('There was a network error.');
  };
  req.send();
}

function sendError(err) {
  console.log(Error);
  gICAPI.Action ("noimage");
};

async function fetchURL(url) {
  try {
    var fetched = await fetch(url);
    console.log("fetch status of url:"+url+",status:"+fetched.status);
    if (!fetched.ok) {
      console.log("not ok!!");
      gICAPI.Action ("noimage");
    } else {
      blob2Base64(await fetched.blob());
    }
  } catch (error) {
    gICAPI.Action( "noimage");
    //alert("error fetch:"+error.message)
    console.error(error.message);
  }
}
