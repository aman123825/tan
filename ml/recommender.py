from collections import defaultdict

def recommend(trials:list[dict]):
    """Explainable rules-first recommender. It never changes locked assessment scoring."""
    if not trials:
        return {'group_id':'sentence_noise','module_id':'noise','reason':'Start with an easy speech-in-noise baseline.','confidence':0.50,'parameters':{'snr_db':12,'mode':'training'}}
    by=defaultdict(list)
    for t in trials:by[(t.get('module_id'),t.get('group_id'))].append(t)
    stats=[]
    for (m,g),xs in by.items():
        acc=sum(int(x.get('correct',0)) for x in xs)/len(xs)
        fatigue=max([x.get('fatigue_after') or 0 for x in xs])
        replay=sum((x.get('replay_count') or 0)>0 for x in xs)/len(xs)
        stats.append((acc,len(xs),fatigue,replay,m,g))
    fatigue=max(x[2] for x in stats)
    if fatigue>=7:
        return {'group_id':'environment','module_id':'foundation','reason':'Recent fatigue was high; choose a shorter, easier non-speech block.','confidence':0.86,'parameters':{'minutes':5,'difficulty':'easy'}}
    weak=sorted(stats,key=lambda x:(x[0],-x[1]))[0]
    acc,n,_,replay,m,g=weak
    if acc<.60:
        reason=f'{g} is the weakest practiced area ({acc:.0%} across {n} trials); reduce complexity without increasing volume.'
        return {'group_id':g,'module_id':m,'reason':reason,'confidence':min(.9,.5+n/50),'parameters':{'difficulty_delta':-1,'target_accuracy':[.70,.85]}}
    untried=[('auditory','gap'),('auditory','modulation_depth'),('noise','sentence_noise'),('assessment','cognition_battery')]
    for m2,g2 in untried:
        if (m2,g2) not in by:return {'group_id':g2,'module_id':m2,'reason':'Collect a balanced baseline in an unmeasured domain.','confidence':.66,'parameters':{'mode':'preview_then_training'}}
    return {'group_id':'sentence_noise','module_id':'noise','reason':'Performance is stable; continue adaptive speech-in-noise at the last successful SNR.','confidence':.72,'parameters':{'target_accuracy':[.70,.85]}}
