//simulates a normal input field in a webco 
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
    img.src=o.src;
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
