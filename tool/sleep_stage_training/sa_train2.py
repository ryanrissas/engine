import sys, numpy as np, warnings; warnings.filterwarnings('ignore')
sys.argv=[sys.argv[0], sys.argv[1]]
exec(open('sa_train.py').read().split("for name, mk in")[0])
from sklearn.ensemble import GradientBoostingClassifier
def vit(P, prior, T, a):
    L=np.log(np.clip(P,1e-9,None))-a*np.log(prior); lT=np.log(T); n=len(L)
    D=np.zeros((n,4)); B=np.zeros((n,4),int); D[0]=L[0]+np.log(prior)
    for i in range(1,n):
        s=D[i-1][:,None]+lT; B[i]=s.argmax(0); D[i]=s.max(0)+L[i]
    p=np.zeros(n,int); p[-1]=D[-1].argmax()
    for i in range(n-1,0,-1): p[i-1]=B[i,p[i]]
    return p
for ne,lr in [(150,0.08),(300,0.05)]:
    P=np.zeros((len(y),4)); T=None
    folds=list(GroupKFold(5).split(X,y,g))
    pv={a:np.zeros(len(y),int) for a in (0.0,0.3,0.5,1.0)}
    for tr,te in folds:
        m=GradientBoostingClassifier(n_estimators=ne,max_depth=3,learning_rate=lr,subsample=0.8,random_state=0).fit(X[tr],y[tr])
        P[te]=m.predict_proba(X[te])
        prior=np.bincount(y[tr],minlength=4)/len(tr)
        T=np.ones((4,4))*1e-3
        for s in np.unique(g[tr]):
            ys_=y[tr][g[tr]==s]
            for a_,b_ in zip(ys_[:-1],ys_[1:]): T[a_,b_]+=1
        T/=T.sum(1,keepdims=True)
        for s in np.unique(g[te]):
            idx=te[g[te]==s]
            for a in pv: pv[a][idx]=vit(P[idx],prior,T,a)
    print('GBT',ne,'argmax',round(cohen_kappa_score(y,P.argmax(1)),3))
    for a,pp in pv.items():
        per=[cohen_kappa_score(y[g==s],pp[g==s]) for s in np.unique(g)]
        print('  viterbi a',a,'pooled',round(cohen_kappa_score(y,pp),3),'median night',round(float(np.median(per)),3),'s/w',round(cohen_kappa_score(y==0,pp==0),3),'share',np.round(np.bincount(pp,minlength=4)/len(pp),3))
