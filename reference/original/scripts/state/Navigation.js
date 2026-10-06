class Navigation{
    static run(){
        Display.clear();
        for(let message of World.getMessages()){
            Display.addSimpleChild("p", message);
        }
        let avatarCharacter = World.getAvatarCharacter();
        Display.addSimpleChild("p",`Character Name: ${avatarCharacter.getName()}`)
        Display.addSimpleChild("p", `XP: ${avatarCharacter.getStatistic(STATISTIC_EXPERIENCE_POINTS)}/${avatarCharacter.getStatistic(STATISTIC_EXPERIENCE_GOAL)} (Level ${avatarCharacter.getStatistic(STATISTIC_EXPERIENCE_LEVEL)})`);
        Display.addSimpleChild("p", `Irritation: ${avatarCharacter.getStatistic(STATISTIC_IRRITATION)}/${avatarCharacter.getStatistic(STATISTIC_MAXIMUM_IRRITATION)}`);
        let lastCheck = avatarCharacter.getStatistic(STATISTIC_LAST_CHECK_TIME);
        if(lastCheck != null){
            let nextRecovery = lastCheck + (AdvancementType.descriptors[ADVANCEMENT_TYPE_IRRITATION_RECOVERY].getEffect(avatarCharacter.getAdvancement(ADVANCEMENT_TYPE_IRRITATION_RECOVERY))*1000);
            Display.addSimpleChild("p",`Next irritation recovery: ${(new Date(nextRecovery)).toLocaleString()}`);
        }
        Display.addSimpleChild("p", `Advancement Points: ${avatarCharacter.getStatistic(STATISTIC_ADVANCEMENT_POINTS)}`);
        Display.addSimpleChild("p",`Butthole Checks: ${avatarCharacter.getStatistic(STATISTIC_BUTTHOLE_CHECKS)}`)
        Display.addButton("Check Butthole", Navigation.checkButthole);
        Display.addButton("Advancements", Navigation.advancements)
        Display.addGameMenuButton();
    }
    static advancements(){
        Advancements.run();
    }
    static checkButthole(){
        World.clearMessages();

        let avatarCharacter = World.getAvatarCharacter();

        Navigation.recoverIrritation(avatarCharacter);

        Navigation.performCheck(avatarCharacter);

        Navigation.handleXPLevelling(avatarCharacter);

        Neutral.run();
    }

    static handleXPLevelling(avatarCharacter) {
        while (avatarCharacter.getStatistic(STATISTIC_EXPERIENCE_POINTS) >= avatarCharacter.getStatistic(STATISTIC_EXPERIENCE_GOAL)) {
            avatarCharacter.changeStatistic(STATISTIC_EXPERIENCE_POINTS, -avatarCharacter.getStatistic(STATISTIC_EXPERIENCE_GOAL));
            avatarCharacter.changeStatistic(STATISTIC_EXPERIENCE_LEVEL, 1);
            World.addMessage(`+${avatarCharacter.getStatistic(STATISTIC_EXPERIENCE_LEVEL)} Advancement Point(s)`);
            avatarCharacter.changeStatistic(STATISTIC_ADVANCEMENT_POINTS, avatarCharacter.getStatistic(STATISTIC_EXPERIENCE_LEVEL));
            World.addMessage(`Yer now level ${avatarCharacter.getStatistic(STATISTIC_EXPERIENCE_LEVEL)}`);
            avatarCharacter.changeStatistic(STATISTIC_EXPERIENCE_GOAL, avatarCharacter.getStatistic(STATISTIC_EXPERIENCE_GOAL));
        }
    }

    static performCheck(avatarCharacter) {
        let irritation = avatarCharacter.getStatistic(STATISTIC_IRRITATION);
        let maximumIrritation = avatarCharacter.getStatistic(STATISTIC_MAXIMUM_IRRITATION);
        if(irritation>=maximumIrritation){
            World.addMessage(`Yer butthole is too irritated!`);
            return;
        }
        World.addMessage("You check yer butthole!");
        World.addMessage(`+1 irritation`);
        avatarCharacter.changeStatistic(STATISTIC_IRRITATION,1);


        let thoroughness = AdvancementType.descriptors[ADVANCEMENT_TYPE_THOROUGHNESS].getEffect(avatarCharacter.getAdvancement(ADVANCEMENT_TYPE_THOROUGHNESS));
        let crit = AdvancementType.descriptors[ADVANCEMENT_TYPE_CRIT].getEffect(avatarCharacter.getAdvancement(ADVANCEMENT_TYPE_CRIT));
        if (Utility.roll(1, 100) <= crit) {
            World.addMessage(`Critical check! Doubly effective!`);
            thoroughness *= 2;
        }
        avatarCharacter.changeStatistic(STATISTIC_BUTTHOLE_CHECKS, thoroughness);
        World.addMessage(`+${thoroughness} XP`);
        avatarCharacter.changeStatistic(STATISTIC_EXPERIENCE_POINTS, thoroughness);
    }
    static recoverIrritation(character){
        let lastCheckTime = character.getStatistic(STATISTIC_LAST_CHECK_TIME);
        let currentTime = Date.now();
        if(lastCheckTime==null){
            lastCheckTime=currentTime;
            character.setStatistic(STATISTIC_LAST_CHECK_TIME, currentTime);
            return;
        }
        let coolDownInterval = AdvancementType.descriptors[ADVANCEMENT_TYPE_IRRITATION_RECOVERY].getEffect(character.getAdvancement(ADVANCEMENT_TYPE_IRRITATION_RECOVERY));
        let recoveryIntervals = Math.floor(((currentTime - lastCheckTime) / 1000) / coolDownInterval);
        lastCheckTime += (recoveryIntervals * coolDownInterval * 1000);
        character.setStatistic(STATISTIC_LAST_CHECK_TIME, lastCheckTime);
        let irritation = character.getStatistic(STATISTIC_IRRITATION);
        recoveryIntervals = Math.min(irritation, recoveryIntervals);
        if(recoveryIntervals>0){
            World.addMessage(`-${recoveryIntervals} Irritation`);
            character.changeStatistic(STATISTIC_IRRITATION, -recoveryIntervals);
        }
    }
}