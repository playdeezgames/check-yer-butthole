class AdvancementDetails{
    static run(advancementType){
        Display.clear();
        let character = World.getAvatarCharacter();
        let descriptor = AdvancementType.descriptors[advancementType];
        Display.addSimpleChild("h3", descriptor.getName());
        Display.addSimpleChild("p", descriptor.getDescription());
        let currentLevel = character.getAdvancement(advancementType);
        if(currentLevel<descriptor.getMaximumLevel()){
            Display.addSimpleChild("p", `Current Level: ${currentLevel} (Effect: ${descriptor.getEffectDescription(currentLevel)})`);
            Display.addSimpleChild("p", `Next Level: ${currentLevel+1} (Effect: ${descriptor.getEffectDescription(currentLevel+1)})`);            
            let cost = descriptor.getCost(currentLevel);
            Display.addSimpleChild("p", `Advancement Cost: ${cost} (You have ${character.getStatistic(STATISTIC_ADVANCEMENT_POINTS)})`);
            if(cost<=character.getStatistic(STATISTIC_ADVANCEMENT_POINTS)){
                Display.addButton("Buy!", ()=>{
                    AdvancementDetails.buy(advancementType);
                });
                Display.addSimpleChild("br");
            }
        }else{
            Display.addSimpleChild("p", `Current Level: MAX (Effect: ${descriptor.getEffectDescription(currentLevel)})`);
        }
        Display.addButton("Go Back", AdvancementDetails.goBack);
    }
    static buy(advancementType){
        let character = World.getAvatarCharacter();
        let descriptor = AdvancementType.descriptors[advancementType];
        let currentLevel = character.getAdvancement(advancementType);
        let cost = descriptor.getCost(currentLevel);
        character.changeStatistic(STATISTIC_ADVANCEMENT_POINTS, -cost);
        character.setAdvancement(advancementType, currentLevel+1);
        AdvancementDetails.run(advancementType);
    }
    static goBack(){
        Advancements.run();
    }
}