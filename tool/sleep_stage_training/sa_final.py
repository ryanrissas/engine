import sys, json, pickle, sqlite3, numpy as np, warnings; warnings.filterwarnings('ignore')
src=sys.argv[1]; sys.argv=[sys.argv[0], src]
exec(open('sa_train.py').read().split("for name, mk in")[0])
from sklearn.ensemble import GradientBoostingClassifier
m=GradientBoostingClassifier(n_estimators=150,max_depth=3,learning_rate=0.08,subsample=0.8,random_state=0).fit(X,y)
prior=np.bincount(y,minlength=4)/len(y)
T=np.ones((4,4))*1e-3
for s in np.unique(g):
    ys_=y[g==s]
    for a_,b_ in zip(ys_[:-1],ys_[1:]): T[a_,b_]+=1
T/=T.sum(1,keepdims=True)
pickle.dump({'model':m,'prior':prior,'T':T},open('sa_model.pkl','wb'))
print('prior',prior.round(4)); print('T',T.round(4))
def vit(P,a=0.5):
    L=np.log(np.clip(P,1e-9,None))-a*np.log(prior); lT=np.log(T); n=len(L)
    D=np.zeros((n,4)); B=np.zeros((n,4),int); D[0]=L[0]+np.log(prior)
    for i in range(1,n):
        s=D[i-1][:,None]+lT; B[i]=s.argmax(0); D[i]=s.max(0)+L[i]
    p=np.zeros(n,int); p[-1]=D[-1].argmax()
    for i in range(n-1,0,-1): p[i-1]=B[i,p[i]]
    return p
# Ryan's nights
db='/tmp/claude-0/-home-claude-engine/6c8f50ab-92aa-53ca-86d0-d125e3452b8c/scratchpad/report2/database_14d.db'
c=sqlite3.connect(db); seen=set()
for day,p in c.execute('select day_id,payload_json from day_result order by day_id'):
    j=json.loads(p); w=j['sleep']['window']['value']
    if not isinstance(w,dict) or day in seen: continue
    seen.add(day); on=int(w['onset_ms']//1000); off=int(w['offset_ms']//1000)
    n=(off-on)//30
    rows=c.execute('select rec_ts,hr,ax,ay,az from decoded_onehz where rec_ts>=? and rec_ts<? order by rec_ts',(on,on+n*30)).fetchall()
    labels=[[on+30*i,0] for i in range(n)]
    hr=[[r[0],r[1]] for r in rows if r[1] and r[1]>0]
    acc=[[r[0],r[2],r[3],r[4]] for r in rows]
    Xr,_=night_features(labels,hr,acc); Xr=np.nan_to_num(Xr,nan=0.0)
    pr=vit(m.predict_proba(Xr)); nm='WLDR'
    sh=np.bincount(pr,minlength=4)/len(pr)
    print(day,'hours',round(n/120,2),'W/L/D/R %',(sh*100).round(1))
    print('  ',''.join(nm[x] for x in pr[::4]))
