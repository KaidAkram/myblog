const https = require('https');
https.get('https://www.myinstants.com/search/?name=vegeta+nani', res => {
  let b='';
  res.on('data', c => b += c);
  res.on('end', () => {
    const m = b.match(/onclick="play\('([^']+)'\)/);
    console.log(m ? m[1] : 'not found');
  });
});
